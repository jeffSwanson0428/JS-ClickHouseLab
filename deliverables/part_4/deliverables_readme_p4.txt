Part 4: Failover and Recovery

For this section I created the script /scripts/sh/failure_simulation.sh which executes the following:
    - Gathers a pod from each replica
    - Creates a new table to insert into
    - Prints each replicas state (count of rows, and replica metadata from system tables)
    - Kills one of the replicas
    - Inserts 30 records into the other (alive) replica
    - Sleeps for a bit to allow the operator to reconcile the killed replica
    - Prints each replicas state again
    - Drops the table, syncs to flush keeper, and checks if the table was deleted (For repeatability)

Each replicas state includes following:
    From system.replcas:
        - database name
        - table name
        - leader status
        - total replicas
        - active replicas
    From system.replication_queue:
        - replication_queue_size: a count() of all records where table = 'failure_sim'
    From system.mutations:
        - mutations_size: acount() of all records where table = 'failure_sim'

Both replicas will have the same values across their corresponding table indicating
that though one replica failed, it was brought back up to speed when came back online.

Here are logs from before the crash on both replicas:

    ### Printing BEFORE state on each pod (row counts + replication status) ###
    # pod: chi-altinity-demo-cluster-1-0-0-0 (BEFORE) #
       ┌─total_rows─┐
    1. │          0 │
       └────────────┘
       ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
    1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
       └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
    # pod: chi-altinity-demo-cluster-1-0-1-0 (BEFORE) #
       ┌─total_rows─┐
    1. │          0 │
       └────────────┘
       ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
    1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
       └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘

Before the crash, neither replica had any data inserted yet, as it was a fresh new table. They also knew about the other nodes in the cluster.

Here are the logs from after the crash and recovery:

    ### Deleting replica 1 pod: chi-altinity-demo-cluster-1-0-1-0 ###
    pod "chi-altinity-demo-cluster-1-0-1-0" deleted
    # Short wait for pod to terminate #

    ### Inserting data into replica 0: chi-altinity-demo-cluster-1-0-0-0 ###

    ### Waiting 30 seconds for operator to recreate pod ###

    ### Printing AFTER state on each pod (row counts + replication status) ###
    # pod: chi-altinity-demo-cluster-1-0-0-0 (AFTER) #
       ┌─total_rows─┐
    1. │         30 │
       └────────────┘
       ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
    1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
       └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
    # pod: chi-altinity-demo-cluster-1-0-1-0 (AFTER) #
       ┌─total_rows─┐
    1. │         30 │
       └────────────┘
       ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
    1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
       └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘

After the crash, both replicas have a total_rows of 30, indicating that the pod that died and came back was backfilled with the new data.
They also both are still aware of the other replicas.





Here are the full logs from failure_simulation.sh:




### Retrieving pods for both CHI replicas ###
#  Found Pods: chi-altinity-demo-cluster-1-0-0-0 chi-altinity-demo-cluster-1-0-1-0 #

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


   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘

### Printing BEFORE state on each pod (row counts + replication status) ###
# pod: chi-altinity-demo-cluster-1-0-0-0 (BEFORE) #
   ┌─total_rows─┐
1. │          0 │
   └────────────┘
   ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
   └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
# pod: chi-altinity-demo-cluster-1-0-1-0 (BEFORE) #
   ┌─total_rows─┐
1. │          0 │
   └────────────┘
   ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
   └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘

### Deleting replica 1 pod: chi-altinity-demo-cluster-1-0-1-0 ###
pod "chi-altinity-demo-cluster-1-0-1-0" deleted
# Short wait for pod to terminate #

### Inserting data into replica 0: chi-altinity-demo-cluster-1-0-0-0 ###

### Waiting 30 seconds for operator to recreate pod ###

### Printing AFTER state on each pod (row counts + replication status) ###
# pod: chi-altinity-demo-cluster-1-0-0-0 (AFTER) #
   ┌─total_rows─┐
1. │         30 │
   └────────────┘
   ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
   └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘
# pod: chi-altinity-demo-cluster-1-0-1-0 (AFTER) #
   ┌─total_rows─┐
1. │         30 │
   └────────────┘
   ┌─database─┬─table───────┬─is_leader─┬─total_replicas─┬─active_replicas─┬─replication_queue_size─┬─mutations_size─┐
1. │ default  │ failure_sim │         1 │              4 │               4 │                      0 │              0 │
   └──────────┴─────────────┴───────────┴────────────────┴─────────────────┴────────────────────────┴────────────────┘

### Finished Simulation! ###

### Preparing cluster for next simulation ###
# Dropping failure_sim and checking existence on each replica #
# chi-altinity-demo-cluster-1-0-0-0 running reset script #
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
   ┌─result─┐
1. │      0 │
   └────────┘
# chi-altinity-demo-cluster-1-0-1-0 running reset script #
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
   ┌─result─┐
1. │      0 │
   └────────┘
