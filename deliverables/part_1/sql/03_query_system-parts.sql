SELECT
    hostName()   AS replica_host,
    name         AS part_name,
    rows,
    active
FROM clusterAllReplicas('cluster-1', 'system', 'parts')
WHERE
    database = 'default'
    AND table = 'test_replication'
    AND active = 1
ORDER BY
    replica_host,
    part_name;
