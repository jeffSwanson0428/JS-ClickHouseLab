SELECT 
    count() AS total_rows
FROM 
    failure_sim
;

SELECT
    database,
    table,
    is_leader,
    total_replicas,
    active_replicas,
    (SELECT count() FROM system.replication_queue WHERE table='failure_sim') AS replication_queue_size,
    (SELECT count() FROM system.mutations WHERE table='failure_sim') AS mutations_size
FROM 
    system.replicas
WHERE
    table = 'failure_sim'
;
