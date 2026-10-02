-- Compara la temperatura actual de cada sensor con su promedio histórico, ordenado por los eventos más recientes y limitado a 20 registros más recientes: 

SELECT
    live.sensor_id,
    live.avg_temperature                          AS temperatura_actual,
    hist.avg_temperature                           AS promedio_historico,
    live.avg_temperature - hist.avg_temperature    AS desvio
FROM analytics_consumption.sensor_events_parsed live
JOIN lakehouse_iceberg.sensor_events hist
    ON live.sensor_id = hist.sensor_id
ORDER BY live.event_time DESC
LIMIT 20;
