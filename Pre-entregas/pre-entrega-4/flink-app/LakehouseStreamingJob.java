package com.coderhouse.lakehouse;

import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kinesis.source.KinesisStreamsSource;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.KeyedStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

import com.amazonaws.services.kinesisanalytics.runtime.KinesisAnalyticsRuntime;

import java.io.Serializable;
import java.time.Duration;
import java.util.Map;
import java.util.Properties;


public class LakehouseStreamingJob {

    public static void main(String[] args) throws Exception {

        // ---- Flink: entorno y checkpoints ----
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(60_000); 

        // Managed Flink expone las environment_properties definidas en el archivo de Terraform flink.tf 
        Map<String, Properties> applicationProperties = KinesisAnalyticsRuntime.getApplicationProperties();

        if (applicationProperties == null) {
            throw new RuntimeException("KinesisAnalyticsRuntime.getApplicationProperties() devolvio null");
        }

        Properties flinkAppProps = applicationProperties.get("FlinkAppProperties");

        if (flinkAppProps == null) {
            throw new RuntimeException(
                    "No se encontro el grupo 'FlinkAppProperties'. Grupos disponibles: "
                            + applicationProperties.keySet());
        }

        String streamArn = flinkAppProps.getProperty("KINESIS_STREAM_ARN");
        String lakehouseBucket = flinkAppProps.getProperty("LAKEHOUSE_BUCKET");

        if (streamArn == null || lakehouseBucket == null) {
            throw new RuntimeException(
                    "Faltan propiedades. Claves encontradas en FlinkAppProperties: "
                            + flinkAppProps.stringPropertyNames()
                            + " -- streamArn=" + streamArn
                            + " lakehouseBucket=" + lakehouseBucket);
        }

        // ---- Consumo del stream de Kinesis con Flink  ----
        // El sourceConfig necesita la region de AWS explicita 
        //  La extraemos del mismo ARN del stream, que tiene
        // el formato arn:aws:kinesis:REGION:ACCOUNT:stream/NOMBRE. el lugar 0 es arn y el lugar 3 es la region
        String awsRegion = streamArn.split(":")[3];

        org.apache.flink.configuration.Configuration sourceConfig =
                new org.apache.flink.configuration.Configuration();
        sourceConfig.setString("aws.region", awsRegion);

        KinesisStreamsSource<String> source = KinesisStreamsSource.<String>builder()
                .setStreamArn(streamArn)
                .setSourceConfig(sourceConfig)
                .setDeserializationSchema(new SimpleStringSchema())
                .build();

        // ---- Consumo del stream de Kinesis: Estrategia watermark para strings----
        // El watermark con un timestamp assigner explicito       
        WatermarkStrategy<String> watermarkStrategy = WatermarkStrategy
                .<String>forBoundedOutOfOrderness(Duration.ofSeconds(10)) // Acepta eventos que pueden llegar hasta 10 segundos fuera de orden.
                .withTimestampAssigner((event, recordTimestamp) -> System.currentTimeMillis()); // Asigna como timestamp el momento en el que Flink procesa/recibe el evento

        DataStream<String> rawEvents = env.fromSource(
                source,
                watermarkStrategy,
                "kinesis-source",
                TypeInformation.of(String.class)
        );

        // ---- Flink: ventana de agregacion stateful ----
        KeyedStream<String, String> keyed = rawEvents.keyBy(LakehouseStreamingJob::extractSensorId);

        // ---- Ventana por TIEMPO DE PROCESAMIENTO ----
        //  Processing time se basa en el reloj de la maquina donde se esta ejecutando Flink
        DataStream<String> aggregated = keyed
                .window(TumblingProcessingTimeWindows.of(Time.minutes(1)))
                .aggregate(new AverageAggregateFunction());

        env.execute("dev-lakehouse-streaming");
        
    }

    // ---- Parseo del sensor_id ----
    private static String extractSensorId(String event) {
        return event.split(",")[0];
    }

    // ---- Funcion de agregacion ----
    // Calcula el promedio de temperatura por sensor dentro de la ventana.
    public static class AverageAggregateFunction
            implements AggregateFunction<String, Accumulator, String> {

        @Override
        public Accumulator createAccumulator() {
            return new Accumulator();
        }

        @Override
        public Accumulator add(String value, Accumulator acc) {
            String[] parts = value.split(",");
            acc.sensorId = parts[0];
            acc.sum += Double.parseDouble(parts[1]);
            acc.count += 1;
            return acc;
        }

        @Override
        public String getResult(Accumulator acc) {
            double avg = acc.count == 0 ? 0.0 : acc.sum / acc.count;
            return acc.sensorId + "," + avg;
        }

        @Override
        public Accumulator merge(Accumulator a, Accumulator b) {
            Accumulator merged = new Accumulator();
            merged.sensorId = (a.sensorId != null) ? a.sensorId : b.sensorId;
            merged.sum = a.sum + b.sum;
            merged.count = a.count + b.count;
            return merged;
        }
    }

    public static class Accumulator implements Serializable {
        String sensorId;
        double sum = 0.0;
        long count = 0;
    }
        
}

