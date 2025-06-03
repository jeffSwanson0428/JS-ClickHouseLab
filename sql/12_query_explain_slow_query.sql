EXPLAIN SELECT
    host,
    length(message),
    lower(message),
    reverse(host),
    toUnixTimestamp(timestamp)
FROM logs
WHERE log_level != ''
ORDER BY
    lower(message),
    reverse(host),
    toUnixTimestamp(timestamp)
LIMIT 1000000
;
