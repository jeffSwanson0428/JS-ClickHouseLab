SELECT
    hostName() AS replica_host,
    database,
    table,
    engine,
    is_leader,
    can_become_leader,
    zookeeper_name,
    zookeeper_path,
    replica_name,
    replica_path,
    total_replicas,
    active_replicas,
    replica_is_active
FROM clusterAllReplicas('cluster-1', 'system', 'replicas')
WHERE database = 'default'
  AND table = 'test_replication'
ORDER BY replica_host;
