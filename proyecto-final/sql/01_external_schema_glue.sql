-- Creacion del schema externo lakehouse_iceberg 

CREATE EXTERNAL SCHEMA lakehouse_iceberg
FROM DATA CATALOG
DATABASE 'lakehouse_db'
IAM_ROLE 'arn:aws:iam::880287985194:role/dev-redshift-streaming-ingest-role'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- Verificación de que se puede consultar los datos de la tabla sensor_events usando el schema externo lacehouse_iceberg  
SELECT * FROM svv_external_tables WHERE schemaname = 'lakehouse_iceberg';
