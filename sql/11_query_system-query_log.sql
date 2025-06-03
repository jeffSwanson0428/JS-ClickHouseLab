SELECT 
    query_start_time,
    query_duration_ms,
    read_rows,
    read_bytes,
    memory_usage,
    result_rows,
    result_bytes,
    query
FROM
    system.query_log
WHERE 
    type = 'QueryFinish'
    AND query ILIKE '%length(message)%lower(message)%LIMIT 1000000%'
ORDER BY
    event_time DESC 
LIMIT 1
;
