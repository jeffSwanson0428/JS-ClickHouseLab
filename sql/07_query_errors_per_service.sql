SELECT
    service_name AS service,
    count() AS total_errors
FROM
    logs
PREWHERE
    log_level = 'Error'
GROUP BY 
    service_name
;
