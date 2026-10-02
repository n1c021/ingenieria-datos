-- Creacion del schema externo kinesis_raw que permite a Redshift consultar directamente datos que llegan desde Kinesis Data Streams 

CREATE EXTERNAL SCHEMA kinesis_raw
FROM KINESIS
IAM_ROLE 'arn:aws:iam::880287985194:role/dev-redshift-streaming-ingest-role';

-- Crea una Materialized View sensor_events_live que actualiza automáticamente la vista con los nuevos eventos de Kinesis. Extrae el sensor_id y la tempoeratura promedio, convirtiéndola en número flotante. 

CREATE MATERIALIZED VIEW sensor_events_live AUTO REFRESH YES AS
SELECT
    approximate_arrival_timestamp,
    partition_key,
    SPLIT_PART(from_varbyte(kinesis_data, 'utf-8'), ',', 1) AS sensor_id,
    SPLIT_PART(from_varbyte(kinesis_data, 'utf-8'), ',', 2)::float AS avg_temperature
FROM kinesis_raw."dev-events-stream";

 
-- Crea si no existe todavia el schema analytics_consumption 
-- Crea la vista sensor_events_parsed que toma de sensor_events_live: 
-- approximate_arrival_timestamp, renombrado como event_time,sensor_id, avg_temperature

CREATE SCHEMA IF NOT EXISTS analytics_consumption;

CREATE VIEW analytics_consumption.sensor_events_parsed AS
SELECT
    approximate_arrival_timestamp AS event_time,
    sensor_id,
    avg_temperature
FROM sensor_events_live;
