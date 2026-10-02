-- Restringe el acceso al schema kinesis_raw al rol publico 

REVOKE ALL ON SCHEMA kinesis_raw FROM PUBLIC;

-- Crea el grupo power_users y se le permite usar el schema analytics_consumption.Da permisos de lectura sobre la vista sensor_events_parsed. 

CREATE GROUP power_users;
GRANT USAGE ON SCHEMA analytics_consumption TO GROUP power_users;
GRANT SELECT ON analytics_consumption.sensor_events_parsed TO GROUP power_users;
