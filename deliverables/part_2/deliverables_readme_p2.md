# Part 2: Schema Design & Ingestion

There are 2 scripts driving this section:

### `/scripts/sh/schema-and-ingestion.sh`, which:
- Retrieves a pod from each replica  
- Creates the replicated `logs` table across both replicas  
- Initiates the Python script `generate_and_ingest_synthetic_logs.py`  
  - Optional input to skip this part if not needed  
- Counts the records in both replicas after ingestion  

### `/scripts/py/generate_and_ingest_synthetic_logs.py`, which:
- Accepts several CLI args  
- Creates a ClickHouse client  
- Generates batches of 100,000 synthetic logs  
- Inserts 10 batches of records into ClickHouse  

---

## `schema-and-ingestion.sh` Logs

```sql
### Creating replicated test table across both replicas ###
CREATE TABLE IF NOT EXISTS logs ON CLUSTER '{cluster}'
(
    timestamp DateTime,
    service_name String,
    host String,
    log_level String,
    message String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/logs','{replica}')
PARTITION BY toYYYYMM(timestamp)
ORDER BY (service_name, timestamp);
```

```
┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
│ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   3 │                0 │
│ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   2 │                0 │
│ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   1 │                0 │
│ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   0 │                0 │
└─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
│ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   3 │                0 │
│ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   2 │                0 │
│ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   1 │                0 │
│ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   0 │                0 │
└─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
```

---

## Ingestion Interaction

```
#########################################
###     Ingest 1M Synthetic Logs?     ###
#########################################
### Proceed with ingestion? [y/n]: y
### Port-forwarding the cluster CHI service http port ###

### Inserting synthetic logs via Python script ###
>>> Inserted batch 1 of 10
>>> Inserted batch 2 of 10
>>> Inserted batch 3 of 10
>>> Inserted batch 4 of 10
>>> Inserted batch 5 of 10
>>> Inserted batch 6 of 10
>>> Inserted batch 7 of 10
>>> Inserted batch 8 of 10
>>> Inserted batch 9 of 10
>>> Inserted batch 10 of 10
>>> All records inserted successfully.
```

---

## Cleanup and Record Counts

```
### Killing port-forward process ###
/Users/jeffswanson/Documents/GitHub/JS-ClickHouseLab/scripts/sh/schema-and-ingestion.sh: line 35:  3711 Terminated: 15          kubectl port-forward -n clickhouse-lab svc/clickhouse-altinity-demo 8123:8123 > /dev/null 2>&1
# Port-forward process (PID 3711) successfully terminated. #

### Counting records stored on pods from each replica ###
SELECT count(*) FROM logs;
```

```
chi-altinity-demo-cluster-1-0-0-0: total records = 
┌─count()─┐
│ 1000000 │
└─────────┘

chi-altinity-demo-cluster-1-0-1-0: total records = 
┌─count()─┐
│ 1000000 │
└─────────┘
```
