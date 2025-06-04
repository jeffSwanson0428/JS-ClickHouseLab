# Project Background Information

I opted to go with **Option B: Kubernetes + ClickHouse Operator**. This came most natural to me as I have worked quite a bit with Kubernetes. For my cluster I utilized the Docker Desktop–provided `kind` cluster, with 1 node running Kubernetes v1.31.1.

## Notes & Requirements

Some things that may trip you up:

- Ensure you can execute the scripts:
  ```sh
  chmod +x /JS-ClickHouseLab/scripts/sh/*
  ```
- Ensure you have the `envsubst` command:
  ```sh
  which envsubst
  ```
  - If not, install via:
    ```sh
    brew install gettext
    ```
- Python is referenced in the shell script with the keyword `python3`.
  - You can change the script to use your preferred keyword.
  - This only applies to `/scripts/sh/schema-and-ingestion.sh` at **line 47**.
- Install required Python packages:
  ```sh
  pip3 install clickhouse-connect
  pip3 install Faker
  ```
- Scripts tested in **bash** and **zsh**; other shells may have issues.

## Usage: `demo.sh`

Each script is executable standalone, but `demo.sh` drives the full process:

- Deploy infrastructure to Kubernetes:
  - Altinity ClickHouse Operator
  - CHI
  - ClickHouse Keeper
- Validate replication and Keeper health
- Create the `logs` table across the cluster
  - Ingest 1 million synthetic logs via Python script
- Run required queries on the `logs` table
- Simulate failure (replica unavailable)
- Teardown infrastructure

Full logs of this process are provided in this directory, along with a log specific to Part 1.

---

# Part 1: Cluster Deployment

Deployment is handled by `/scripts/sh/up.sh`, which does the following:

- Source env vars from `/scripts/sh/env.sh`
- Substitute env vars in the ClickHouse Operator template to generate a manifest
- Create namespace and apply manifests

### Logs from `up.sh`

```sh
### Creating namespaces: ###
namespace/clickhouse-lab created
namespace/prometheus created

### Creating Altinity Clickhouse Operator ###
customresourcedefinition.apiextensions.k8s.io/clickhouseinstallations.clickhouse.altinity.com created
customresourcedefinition.apiextensions.k8s.io/clickhouseinstallationtemplates.clickhouse.altinity.com created
customresourcedefinition.apiextensions.k8s.io/clickhouseoperatorconfigurations.clickhouse.altinity.com created
customresourcedefinition.apiextensions.k8s.io/clickhousekeeperinstallations.clickhouse-keeper.altinity.com created
serviceaccount/clickhouse-operator created
clusterrole.rbac.authorization.k8s.io/clickhouse-operator-clickhouse-lab created
clusterrolebinding.rbac.authorization.k8s.io/clickhouse-operator-clickhouse-lab created
configmap/etc-clickhouse-operator-files created
configmap/etc-clickhouse-operator-confd-files created
configmap/etc-clickhouse-operator-configd-files created
configmap/etc-clickhouse-operator-templatesd-files created
configmap/etc-clickhouse-operator-usersd-files created
configmap/etc-keeper-operator-confd-files created
configmap/etc-keeper-operator-configd-files created
configmap/etc-keeper-operator-templatesd-files created
configmap/etc-keeper-operator-usersd-files created
secret/clickhouse-operator created
deployment.apps/clickhouse-operator created
service/clickhouse-operator-metrics created

### Creating Clickhouse Keeper ###
clickhousekeeperinstallation.clickhouse-keeper.altinity.com/clickhouse-keeper created

### Creating Clickhouse Installation ###
clickhouseinstallation.clickhouse.altinity.com/altinity-demo created
### Sleeping for 3 minutes to allow pods to come up (Sorry!) ###
```

---

## Validating Replication: `test-replication-and-health.sh`

This script performs:

- Retrieves a CHI pod for each replica
- Creates replicated `test_replication` table across replicas
- Inserts into one replica, queries from another
- Queries `system.parts` to confirm replication
- Lists Keeper pod status
- Uses `clickhouse-client` on Keeper pods to check zNode creation
- Queries `system.replicas` for replication metadata

### Key Logs & Outputs

```sh
### Retrieving a CHI pod from each replica ###
# Found Pods: chi-altinity-demo-cluster-1-0-0-0 chi-altinity-demo-cluster-1-0-1-0 #
```

#### Table Creation On Both Replicas & Output

```sql
CREATE TABLE IF NOT EXISTS test_replication ON CLUSTER '{cluster}'
(
    event_id UInt64,
    event_time DateTime
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/events',
    '{replica}'
)
ORDER BY (event_id);
```

```bash
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
1. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   3 │                0 │
2. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   2 │                0 │
3. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   1 │                0 │
4. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
   ┌─host────────────────────────────┬─port─┬─status─┬─error─┬─num_hosts_remaining─┬─num_hosts_active─┐
5. │ chi-altinity-demo-cluster-1-1-1 │ 9000 │      0 │       │                   3 │                0 │
6. │ chi-altinity-demo-cluster-1-1-0 │ 9000 │      0 │       │                   2 │                0 │
7. │ chi-altinity-demo-cluster-1-0-0 │ 9000 │      0 │       │                   1 │                0 │
8. │ chi-altinity-demo-cluster-1-0-1 │ 9000 │      0 │       │                   0 │                0 │
   └─────────────────────────────────┴──────┴────────┴───────┴─────────────────────┴──────────────────┘
```

#### Table Insert From One Replica

```sql
INSERT INTO test_replication (event_id, event_time)
VALUES
    (1, now()),
    (2, '1995-04-28 12:34:56'),
    (3, now());
```

#### Query & Output From Other Replica

```sql
SELECT * FROM test_replication;
┌─event_id─┬──────────event_time─┐
│       1  │ 2025-06-04 01:25:51 │
│       2  │ 1995-04-28 12:34:56 │
│       3  │ 2025-06-04 01:25:51 │
└──────────┴─────────────────────┘
```

#### `system.parts` Query & Output

```sql
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
```
```bash
    part_name;
   ┌─replica_host──────────────────────┬─part_name─┬─rows─┬─active─┐
1. │ chi-altinity-demo-cluster-1-0-0-0 │ all_0_0_0 │    3 │      1 │
2. │ chi-altinity-demo-cluster-1-0-1-0 │ all_0_0_0 │    3 │      1 │
3. │ chi-altinity-demo-cluster-1-1-0-0 │ all_0_0_0 │    3 │      1 │
4. │ chi-altinity-demo-cluster-1-1-1-0 │ all_0_0_0 │    3 │      1 │
   └───────────────────────────────────┴───────────┴──────┴────────┘
```

#### Keeper Pod Status

```
chk-clickhouse-keeper-chk01-0-0-0: Running
chk-clickhouse-keeper-chk01-0-1-0: Running
chk-clickhouse-keeper-chk01-0-2-0: Running
```

#### Keeper replica is_active validation

```sh
### Checking is_active for each replica on Clickhouse-Keeper ###
#  Validating chi-altinity-demo-cluster-1-0-0 is active #
UUID_'a5a469be-af98-4074-bc5e-cf42f0e08af5'

#  Validating chi-altinity-demo-cluster-1-0-1 is active #
UUID_'5aff6ffc-cd97-4ef4-af6d-1dc27cff1c56'

#  Validating chi-altinity-demo-cluster-1-1-0 is active #
UUID_'0e4f71d3-9688-4ce1-802f-fa0a1e10c5ca'

#  Validating chi-altinity-demo-cluster-1-1-1 is active #
UUID_'2e01acc8-b3c3-4fff-950e-ff2300276a47'
...
```

#### `system.replicas` Query & Output

```sql
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
```
```bash
Row 1:
──────
replica_host:      chi-altinity-demo-cluster-1-0-0-0
database:          default
table:             test_replication
engine:            ReplicatedMergeTree
keeper_name:       default
replica_name:      chi-altinity-demo-cluster-1-0-0
replica_path:      /clickhouse/tables/cluster-1/events/replicas/chi-altinity-demo-cluster-1-0-0
total_replicas:    4
replica_is_active: {'chi-altinity-demo-cluster-1-0-0':1,'chi-altinity-demo-cluster-1-0-1':1,'chi-altinity-demo-cluster-1-1-0':1,'chi-altinity-demo-cluster-1-1-1':1}

Row 2:
──────
replica_host:      chi-altinity-demo-cluster-1-0-1-0
database:          default
table:             test_replication
engine:            ReplicatedMergeTree
keeper_name:       default
replica_name:      chi-altinity-demo-cluster-1-0-1
replica_path:      /clickhouse/tables/cluster-1/events/replicas/chi-altinity-demo-cluster-1-0-1
total_replicas:    4
replica_is_active: {'chi-altinity-demo-cluster-1-0-0':1,'chi-altinity-demo-cluster-1-1-1':1,'chi-altinity-demo-cluster-1-1-0':1,'chi-altinity-demo-cluster-1-0-1':1}

Row 3:
──────
replica_host:      chi-altinity-demo-cluster-1-1-0-0
database:          default
table:             test_replication
engine:            ReplicatedMergeTree
keeper_name:       default
replica_name:      chi-altinity-demo-cluster-1-1-0
replica_path:      /clickhouse/tables/cluster-1/events/replicas/chi-altinity-demo-cluster-1-1-0
total_replicas:    4
replica_is_active: {'chi-altinity-demo-cluster-1-0-0':1,'chi-altinity-demo-cluster-1-0-1':1,'chi-altinity-demo-cluster-1-1-0':1,'chi-altinity-demo-cluster-1-1-1':1}

Row 4:
──────
replica_host:      chi-altinity-demo-cluster-1-1-1-0
database:          default
table:             test_replication
engine:            ReplicatedMergeTree
keeper_name:       default
replica_name:      chi-altinity-demo-cluster-1-1-1
replica_path:      /clickhouse/tables/cluster-1/events/replicas/chi-altinity-demo-cluster-1-1-1
total_replicas:    4
replica_is_active: {'chi-altinity-demo-cluster-1-0-0':1,'chi-altinity-demo-cluster-1-0-1':1,'chi-altinity-demo-cluster-1-1-0':1,'chi-altinity-demo-cluster-1-1-1':1}
```
