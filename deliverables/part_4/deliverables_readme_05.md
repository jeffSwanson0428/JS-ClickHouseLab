# Part 4: Failover and Recovery

This section executes the script `/scripts/sh/failure_simulation.sh`, performing the following:

- Gathers a pod from each replica  
- Creates a new table to insert into  
- Prints each replica's state (row counts + replication metadata)  
- Kills one of the replicas  
- Inserts 30 records into the other (alive) replica  
- Sleeps to allow the operator to reconcile the killed replica  
- Prints each replica's state again  
- Drops the table, syncs Keeper, and checks deletion (for repeatability)  

Each replica’s state includes:

From `system.replicas`:
- `database`  
- `table`  
- `is_leader`  
- `total_replicas`  
- `active_replicas`  

From `system.replication_queue`:
- `replication_queue_size`: `count()` where `table = 'failure_sim'`  

From `system.mutations`:
- `mutations_size`: `count()` where `table = 'failure_sim'`  

Both replicas will have the same values across these tables, confirming that after failure and recovery, data remains consistent.

---
## Creating failure_sim table & output

```sql
### Creating failure_sim table on each replica ###
CREATE TABLE IF NOT EXISTS failure_sim ON CLUSTER '{cluster}'
(
    event_id UInt64,
    event_time DateTime
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/failure_sim',
    '{replica}'
)
ORDER BY (event_id);
```
```
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
```

---
## State Before the Crash

### pod: chi-altinity-demo-cluster-1-0-0-0 (BEFORE) state #
```sql
SELECT count(*) AS total_rows FROM failure_sim;

┌─total_rows─┐
│          0 │
└────────────┘
```

```sql
SELECT
    database,
    table,
    is_leader,
    total_replicas,
    active_replicas,
    (SELECT count() FROM system.replication_queue WHERE table = 'failure_sim') AS replication_queue_size,
    (SELECT count() FROM system.mutations WHERE table = 'failure_sim') AS mutations_size
FROM system.replicas
WHERE table = 'failure_sim';

┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
│ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
└──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
```


### pod: chi-altinity-demo-cluster-1-0-1-0 (BEFORE) #


```sql
SELECT count(*) AS total_rows FROM failure_sim;

┌─total_rows─┐
│          0 │
└────────────┘
```

```sql
SELECT
    database,
    table,
    is_leader,
    total_replicas,
    active_replicas,
    (SELECT count() FROM system.replication_queue WHERE table = 'failure_sim') AS replication_queue_size,
    (SELECT count() FROM system.mutations WHERE table = 'failure_sim') AS mutations_size
FROM system.replicas
WHERE table = 'failure_sim';

┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
│ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
└──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
```

---

## Crashing one replicas pod, inserting on the other

```bash
### Deleting replica 1 pod: chi-altinity-demo-cluster-1-0-1-0 ###
pod "chi-altinity-demo-cluster-1-0-1-0" deleted
# Short wait for pod to terminate #
```
```sql
### Inserting data into replica 0: chi-altinity-demo-cluster-1-0-0-0 ###

INSERT INTO failure_sim (event_id,event_time)
VALUES
    (1, '2023-01-01 08:00:00'),(2, '2023-01-01 14:00:00'),(3, '2023-01-01 20:00:00'),
    (4, '2023-01-02 02:00:00'),(5, '2023-01-02 08:00:00'),(6, '2023-01-02 14:00:00'),
    (7, '2023-01-02 20:00:00'),(8, '2023-01-03 02:00:00'),(9, '2023-01-03 08:00:00'),
    (10,'2023-01-03 14:00:00'),(11,'2023-01-03 20:00:00'),(12,'2023-01-04 02:00:00'),
    (13,'2023-01-04 08:00:00'),(14,'2023-01-04 14:00:00'),(15,'2023-01-04 20:00:00'),
    (16,'2023-01-05 02:00:00'),(17,'2023-01-05 08:00:00'),(18,'2023-01-05 14:00:00'),
    (19,'2023-01-05 20:00:00'),(20,'2023-01-06 02:00:00'),(21,'2023-01-06 08:00:00'),
    (22,'2023-01-06 14:00:00'),(23,'2023-01-06 20:00:00'),(24,'2023-01-07 02:00:00'),
    (25,'2023-01-07 08:00:00'),(26,'2023-01-07 14:00:00'),(27,'2023-01-07 20:00:00'),
    (28,'2023-01-08 02:00:00'),(29,'2023-01-08 08:00:00'),(30,'2023-01-08 14:00:00');
;

```

## State After the Crash ###
### pod: chi-altinity-demo-cluster-1-0-0-0 (AFTER) state #


```sql
SELECT count(*) AS total_rows FROM failure_sim;

┌─total_rows─┐
│         30 │
└────────────┘
```

```sql
SELECT
    database,
    table,
    is_leader,
    total_replicas,
    active_replicas,
    (SELECT count() FROM system.replication_queue WHERE table = 'failure_sim') AS replication_queue_size,
    (SELECT count() FROM system.mutations WHERE table = 'failure_sim') AS mutations_size
FROM system.replicas
WHERE table = 'failure_sim';

┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
│ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
└──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
```


### pod: chi-altinity-demo-cluster-1-0-1-0 (AFTER) state #


```sql
SELECT count(*) AS total_rows FROM failure_sim;

┌─total_rows─┐
│         30 │
└────────────┘
```

```sql
SELECT
    database,
    table,
    is_leader,
    total_replicas,
    active_replicas,
    (SELECT count() FROM system.replication_queue WHERE table = 'failure_sim') AS replication_queue_size,
    (SELECT count() FROM system.mutations WHERE table = 'failure_sim') AS mutations_size
FROM system.replicas
WHERE table = 'failure_sim';

┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
│ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
└──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
```
