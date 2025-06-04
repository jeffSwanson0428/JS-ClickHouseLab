SELECT
    host,
    length(message),
    lower(message),
    lower(host),
    reverse(toString(timestamp))
FROM logs
WHERE log_level != ''
ORDER BY
    lower(message),
    lower(host),
    toUnixTimestamp(timestamp)
LIMIT 1000000
;
