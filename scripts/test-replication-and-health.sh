#!/bin/bash
set -e
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/env.sh"

# Confirm replication is working by creating a table on both replicas, inserting on one, and querying from the other.
echo -e "\n### Retrieving a CHI pod from each replica ###"
chi_pods=(
    $( kubectl get pods \
     -n "$NAMESPACE" \
     -l "clickhouse.altinity.com/cluster=cluster-1,clickhouse.altinity.com/shard=0" \
     -o jsonpath='{.items[*].metadata.name}' \
     )
)

if [[ -z "$chi_pods" ]]; then
    echo "#  No pods found. Ensure the environment is up by running up.sh  #"
    exit 1
fi
echo "#  Found Pods: ${chi_pods[@]} #"

echo -e "\n### Creating replicated test table across replicas ###"
cat "$LAB_ROOT/sql/00_create_test_replication_table.sql"
for pod in "${chi_pods[@]}"; do
    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/00_create_test_replication_table.sql"
done

echo -e "\n### Inserting into table on node ${chi_pods[0]} ###"
cat "$LAB_ROOT/sql/01_insert_into_one_node.sql"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[0]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/01_insert_into_one_node.sql"

echo -e "\n### Querying table from ${chi_pods[1]} ###"
cat "$LAB_ROOT/sql/02_query_from_other_node.sql" 
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/02_query_from_other_node.sql" 

# Query system.parts to show the insert was properly replicated across all nodes
# Should output {CHI-POD-NAME, all_0_0_0, 3, 1} for each CHI pod
echo -e '\n### Querying system.parts ###'
cat "$LAB_ROOT/sql/03_query_system-parts.sql"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[0]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/03_query_system-parts.sql"

# Show Clickhouse Keeper CRD status using kubectl
keeper_pods=(
    $( kubectl get pods \
     -n "$NAMESPACE" \
     -l "clickhouse-keeper.altinity.com/chk=clickhouse-keeper" \
     -o jsonpath='{.items[*].metadata.name}' \
    )
)
echo -e "\n### Listing pod status for all Clickhouse-Keeper pods ###"
for pod in "${keeper_pods[@]}"; do
  status=$(kubectl get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.status.phase}')
  printf '%s: %s\n' "$pod" "$status"
done


# Show Clickhouse Keeper State, indicating the nodes have registered with Keeper.
# TODO: programmatically retrieve replicas. "ls  "/clickhouse/tables/cluster-1/events/replicas/"" in clickhouse-keeper-client lists them, 
#       but returns them with strange whitespace characters causing unexpected behavior.
replicas=("chi-altinity-demo-cluster-1-0-0" "chi-altinity-demo-cluster-1-0-1" "chi-altinity-demo-cluster-1-1-0" "chi-altinity-demo-cluster-1-1-1")
pod_name=${keeper_pods[1]}
echo -e "\n### Checking is_active for each replica on Clickhouse-Keeper ###"
# For each replica, validate is_active is not null, indicating the znode was created when the node registered with keeper for replication.
for r in "${replicas[@]}"; do
    echo "#  Validating $r is active #"
    kubectl exec -n "$NAMESPACE" "$pod_name" -c "$CLICKHOUSE_KEEPER_CONTAINER" -- \
    sh -c "echo \"get \\\"/clickhouse/tables/cluster-1/events/replicas/$r/is_active\\\";\" \
      | clickhouse-keeper-client --host 127.0.0.1 --port 2181 2>/dev/null"
done

# Query system.replicas to show each node contains the same replication metadata about default.test_replication and correctly connected with clickhouse-keeper
echo -e '\n### Querying system.replicas for replication metadata ###'
cat "$LAB_ROOT/sql/04_query_system-replicas.sql"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[0]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/04_query_system-replicas.sql" \
    | column -t -s $'\t'
