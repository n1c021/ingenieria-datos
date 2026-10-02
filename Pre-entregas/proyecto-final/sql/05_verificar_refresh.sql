
-- Diagnostico: por que fallo (o no) el ultimo refresh de la MV.

SELECT *
FROM SVL_MV_REFRESH_STATUS
WHERE mv_name = 'sensor_events_live'
ORDER BY start_time DESC
LIMIT 5;


