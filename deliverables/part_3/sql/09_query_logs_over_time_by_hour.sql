SELECT
    toStartOfHour(timestamp) AS date_to_hour,
    count() AS logs_count
FROM 
	logs
GROUP BY
    date_to_hour
ORDER BY
    date_to_hour
;
