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
import org.apache.flink.table.data.GenericRowData;
import org.apache.flink.table.data.RowData;
import org.apache.flink.table.data.StringData;

import org.apache.hadoop.conf.Configuration;

import org.apache.iceberg.Schema;
import org.apache.iceberg.catalog.Catalog;
import org.apache.iceberg.catalog.TableIdentifier;
import org.apache.iceberg.flink.CatalogLoader;
import org.apache.iceberg.flink.TableLoader;
import org.apache.iceberg.flink.sink.FlinkSink;
import org.apache.iceberg.types.Types;

import com.amazonaws.services.kinesisanalytics.runtime.KinesisAnalyticsRuntime;

import java.io.Serializable;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;


public class LakehouseStreamingJob {

    public static void main(String[] args) throws Exception {

        
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(60_000); 

            
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

                
        String awsRegion = streamArn.split(":")[3];

        org.apache.flink.configuration.Configuration sourceConfig =
                new org.apache.flink.configuration.Configuration();
        sourceConfig.setString("aws.region", awsRegion);

        KinesisStreamsSource<String> source = KinesisStreamsSource.<String>builder()
                .setStreamArn(streamArn)
                .setSourceConfig(sourceConfig)
                .setDeserializationSchema(new SimpleStringSchema())
                .build();

               
        WatermarkStrategy<String> watermarkStrategy = WatermarkStrategy
                .<String>forBoundedOutOfOrderness(Duration.ofSeconds(10))
                .withTimestampAssigner((event, recordTimestamp) -> System.currentTimeMillis());

        DataStream<String> rawEvents = env.fromSource(
                source,
                watermarkStrategy,
                "kinesis-source",
                TypeInformation.of(String.class)
        );

        
        KeyedStream<String, String> keyed = rawEvents.keyBy(LakehouseStreamingJob::extractSensorId);

               
        DataStream<String> aggregated = keyed
                .window(TumblingProcessingTimeWindows.of(Time.minutes(1)))
                .aggregate(new AverageAggregateFunction());

        // ---- Catalogo Glue para Iceberg ----
        Map<String, String> catalogProps = new HashMap<>();
        catalogProps.put("type", "iceberg");
        catalogProps.put("catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog");
        catalogProps.put("warehouse", "s3://" + lakehouseBucket + "/lakehouse/");
        catalogProps.put("io-impl", "org.apache.iceberg.aws.s3.S3FileIO");

        // La firma real de CatalogLoader.custom exige un Configuration
        // de Hadoop, aunque Glue no use HDFS -- es un requisito de la
        // API, no de la logica de negocio.
        CatalogLoader catalogLoader = CatalogLoader.custom(
                "glue_catalog",
                catalogProps,
                new Configuration(),
                "org.apache.iceberg.aws.glue.GlueCatalog"
        );

        TableIdentifier tableId = TableIdentifier.of("lakehouse_db", "sensor_events");

        // ---- Crear la tabla si todavia no existe ----
        Catalog catalog = catalogLoader.loadCatalog();
        if (!catalog.tableExists(tableId)) {
            Schema schema = new Schema(
                    Types.NestedField.required(1, "sensor_id", Types.StringType.get()),
                    Types.NestedField.required(2, "avg_temperature", Types.DoubleType.get()),
                    Types.NestedField.required(3, "event_time_millis", Types.LongType.get())
            );
            catalog.createTable(tableId, schema);
        }

        TableLoader tableLoader = TableLoader.fromCatalog(catalogLoader, tableId);

        
        DataStream<RowData> rowDataStream = aggregated.map(new ToRowDataMapper());

        FlinkSink.forRowData(rowDataStream)
                .tableLoader(tableLoader)
                .append();

        env.execute("clase5-lakehouse-streaming");
    }

    
    private static String extractSensorId(String event) {
        return event.split(",")[0];
    }

    
    
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

    // ---- Pasar el resultado agregado a RowData ----
    public static class ToRowDataMapper implements MapFunction<String, RowData> {
        @Override
        public RowData map(String value) {
            String[] parts = value.split(",");
            GenericRowData row = new GenericRowData(3);
            row.setField(0, StringData.fromString(parts[0]));
            row.setField(1, Double.parseDouble(parts[1]));
            row.setField(2, System.currentTimeMillis());
            return row;
        }
    }
}
