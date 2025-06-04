SELECT
    hostName() AS replica_host,
    database,
    table,
    engine,
    zookeeper_name AS keeper_name,
    replica_name,
    replica_path,
    total_replicas,
    replica_is_active
FROM clusterAllReplicas('cluster-1', 'system', 'replicas')
WHERE database = 'default'
  AND table = 'test_replication'
ORDER BY replica_host;
