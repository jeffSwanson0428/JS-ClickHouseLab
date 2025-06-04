SELECT
	host,
	count()
FROM
	logs
GROUP By
	host
;
