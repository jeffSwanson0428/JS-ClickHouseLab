# ClickHouse Kubernetes Demo

A hands-on demo that deploys a replicated ClickHouse cluster on Kubernetes using Altinity’s ClickHouse Operator, ingests 1 million synthetic log records, exercises performance queries, and simulates a replica failover/recovery.

---

## How It’s Made

**Tech Stack:**

- **Kubernetes** (tested on Docker Desktop’s kind v1.31.1)  
- **Altinity ClickHouse Operator** (manages CustomResourceDefinitions for CHI & Keeper)  
- **ClickHouse** (v23-series servers in a 2-shard, 2-replica topology)  
- **ClickHouse Keeper** (Zookeeper-style coordination)  
- **Bash** (orchestration scripts)  
- **Python 3 + Faker** (generates/inserts synthetic logs via `clickhouse-connect`)  
- **YAML Manifests** (for Operator, Keeper, CHI)  
- **kubectl** (interacts with the cluster)

**Overview:**

1. **Deploy Kubernetes Infrastructure (`up.sh`):**  
   - Creates namespaces `clickhouse-lab` and `prometheus`.  
   - Renders & applies the ClickHouse Operator manifest via `envsubst`.  
   - Applies ClickHouse Keeper and ClickHouseInstallation (CHI, 2 shards × 2 replicas).  

2. **Validate Replication & Keeper (`test-replication-and-health.sh`):**  
   - Creates a small replicated test table (`test_replication`).  
   - Inserts rows on one replica, queries on another to confirm propagation.  
   - Verifies `system.parts` across all CHI nodes.  
   - Lists Keeper pod statuses & checks zNodes via `clickhouse-keeper-client`.  
   - Queries `system.replicas` to ensure metadata consistency.

3. **Create Schema & Ingest Logs (`schema-and-ingestion.sh`):**  
   - Creates a large replicated `logs` table partitioned by `toYYYYMM(timestamp)` and ordered by `(service_name, timestamp)`.  
   - Port-forwards ClickHouse HTTP port (8123) to run `generate_and_ingest_synthetic_logs.py`.  
   - Python script generates 1 million fake log entries (batches of 100 000) using Faker and HTTP INSERTs.  
   - Counts total rows on each replica to confirm ingestion.

4. **Query Performance Tests (`query_performance.sh`):**  
   - Counts error-level logs by service (`07_query_errors_per_service.sql`).  
   - Counts logs per host (`08_query_traffic_per_host.sql`).  
   - Builds an hourly histogram (`09_query_logs_over_time_by_hour.sql`; output suppressed).  
   - Enables `log_queries = 1`.  
   - Executes a deliberately slow query (sorting on computed fields; suppressed).  
   - Queries `system.query_log` for metrics of the slow query.  
   - Runs `EXPLAIN` on the slow query to inspect the plan.  

5. **Failover Simulation (`failure_simulation.sh`):**  
   - Creates a replicated `failure_sim` table.  
   - Queries each replica’s health (row counts, `system.replicas`, `system.replication_queue`, `system.mutations`).  
   - Deletes one replica’s pod, inserts 30 rows into the other replica.  
   - Waits for the operator to recreate the deleted pod, then re-queries health—both replicas should have 30 rows and zero queue/mutations.  
   - Drops `failure_sim` on both replicas and verifies deletion for repeatability.

6. **Tear Down (`down.sh`):**  
   - Deletes CHI, Keeper, and Operator manifests.  
   - Deletes namespaces `prometheus` and `clickhouse-lab`, waiting for deletion.

---

## Environment Setup

1. **Kubernetes Cluster**  
   - Ensure you have a running Kubernetes cluster (e.g., Docker Desktop’s kind).  
   - Confirm `kubectl` is pointed at that cluster.

2. **Install `envsubst`**  
   ```sh
   brew install gettext && brew link --force gettext
   ```
   - `envsubst` is used to render the Operator YAML.

3. **Python & Pip Packages**  
   ```sh
   python3 --version   # v3.7+ recommended
   pip3 install clickhouse-connect Faker
   ```

4. **Clone This Repository**  
   ```sh
   git clone <this-repo-url>
   cd <repo-folder>
   ```

5. **Make Scripts Executable**  
   ```sh
   chmod +x scripts/sh/*.sh
   ```

---

## Running

Execute the high-level orchestration script:

```sh
bash scripts/sh/demo.sh
```

You will be prompted at each stage (y/n) to:

1. **Deploy the Cluster** (`up.sh`)  
2. **Validate Replication & Keeper** (`test-replication-and-health.sh`)  
3. **Create Schema & Ingest Data** (`schema-and-ingestion.sh`)  
4. **Run Query Performance Tests** (`query_performance.sh`)  
5. **Simulate Failover & Recovery** (`failure_simulation.sh`)  
6. **Tear Down Resources** (`down.sh`)

Selecting “y” for each step runs the corresponding script; selecting “n” skips to the next step.

---

## Teardown

If you wish to tear everything down manually at any time, run:

```sh
bash scripts/sh/down.sh
```

This will:

- Delete the ClickHouseInstallation (CHI)  
- Delete the ClickHouse Keeper  
- Delete the ClickHouse Operator  
- Delete namespaces `prometheus` and `clickhouse-lab` (waiting for deletion)

Verify that no leftover namespace remains:

```sh
kubectl get namespace | grep clickhouse-lab
```

If it still exists, delete manually:

```sh
kubectl delete namespace clickhouse-lab
```

---

## Key SQL Files

- **`00_create_test_replication_table.sql`**  
  Creates a simple replicated table `test_replication(event_id UInt64, event_time DateTime)`.

- **`01_insert_into_one_node.sql`**  
  Inserts three sample rows into `test_replication`.

- **`02_query_from_other_node.sql`**  
  Reads all rows from `test_replication` on the second replica.

- **`03_query_system-parts.sql`**  
  Queries `system.parts` to confirm replication for `test_replication`.

- **`04_query_system-replicas.sql`**  
  Queries `system.replicas` for metadata consistency on `test_replication`.

- **`05_create_replicated_logs_table.sql`**  
  Creates a large replicated `logs` table (`timestamp DateTime, service_name String, host String, log_level String, message String`), partitioned by month and ordered by service name + timestamp.

- **`06_count_logs_records.sql`**  
  Counts total rows in `logs`.

- **`07_query_errors_per_service.sql`**  
  Counts `Error`-level logs grouped by `service_name` (uses `PREWHERE`).

- **`08_query_traffic_per_host.sql`**  
  Counts log rows grouped by `host`.

- **`09_query_logs_over_time_by_hour.sql`**  
  Aggregates log counts per hour (`toStartOfHour(timestamp)`). Output is large, suppressed in the script; view logs under `part_3/logs/`.

- **`10_slow_query.sql`**  
  A deliberately slow query that selects:  
  ```sql
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
  LIMIT 1000000;
  ```

- **`11_query_system-query_log.sql`**  
  Queries `system.query_log` for the most recent slow query’s metrics (duration, read_rows, read_bytes, etc.).

- **`12_query_explain_slow_query.sql`**  
  Runs `EXPLAIN` on the slow query to show the execution plan.

- **`13_create_failure_sim_table.sql`**  
  Creates a replicated `failure_sim(event_id UInt64, event_time DateTime)` table.

- **`14_query_replica_health.sql`**  
  Retrieves:
  - `SELECT count(*) AS total_rows FROM failure_sim;`  
  - `SELECT database, table, is_leader, total_replicas, active_replicas FROM system.replicas WHERE table = 'failure_sim';`  
  - `SELECT count() FROM system.replication_queue WHERE table = 'failure_sim';`  
  - `SELECT count() FROM system.mutations WHERE table = 'failure_sim';`

- **`15_insert_during_failure.sql`**  
  Inserts 30 rows into `failure_sim` (to simulate writes during a replica outage).

- **`16_reset_fail_sim_table.sql`**  
  Drops `failure_sim` on each replica and verifies via:
  ```sql
  DROP TABLE IF EXISTS failure_sim ON CLUSTER '{cluster}' SYNC;
  SELECT count() FROM system.tables WHERE name = 'failure_sim';
  ```

---

## Configuration & Environment

All environment settings live in `scripts/sh/env.sh`. Adjust as needed:

```bash
# scripts/sh/env.sh

# Project root (lab root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LAB_ROOT=$PROJECT_ROOT

# ClickHouse Operator settings
export OPERATOR_NAMESPACE=clickhouse-lab
export OPERATOR_IMAGE=altinity/clickhouse-operator:latest
export OPERATOR_IMAGE_PULL_POLICY=IfNotPresent
export METRICS_EXPORTER_IMAGE=altinity/metrics-exporter:latest
export METRICS_EXPORTER_IMAGE_PULL_POLICY=IfNotPresent

# Kubernetes / ClickHouse variables
export NAMESPACE=clickhouse-lab
export CLICKHOUSE_CHI_CONTAINER=clickhouse
export CLICKHOUSE_KEEPER_CONTAINER=clickhouse-keeper
export CLICKHOUSE_TCP_PORT=9000

export CLICKHOUSE_HOST="localhost"
export CLICKHOUSE_HTTP_PORT=8123
export CLICKHOUSE_USER=default
export CLICKHOUSE_PASSWORD=""
export CLICKHOUSE_DATABASE="default"
export CLICKHOUSE_TABLE="logs"
```

- Change `CLICKHOUSE_PASSWORD` if your cluster requires authentication.  
- Adjust `NAMESPACE` if you prefer a different Kubernetes namespace.  

---

## Optimizations

- The deliberately slow query sorts on computed columns (`lower(message)`, `lower(host)`, etc.).  
- **Suggested Improvement:**  
  1. **Materialized View**: Precompute `lower(message)` → `message_lower` and `reverse(host)` → `rev_host`.  
  2. Store these in new columns so that at insert time, transformations happen only once.  
  3. Create an index/`ORDER BY (message_lower, rev_host)` on the materialized view for much faster sorts at query time.  
