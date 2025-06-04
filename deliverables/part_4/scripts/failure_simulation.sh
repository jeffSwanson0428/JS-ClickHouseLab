#!/bin/bash
set -e
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/env.sh"

# Gather a pod from each replica
echo -e "\n### Retrieving pods for both CHI replicas ###"
chi_pods=(
    $( kubectl get pods -n "$NAMESPACE" \
        -l "clickhouse.altinity.com/cluster=cluster-1,clickhouse.altinity.com/shard=0" \
        -o jsonpath='{.items[*].metadata.name}' \
    )
)
if [[ ${#chi_pods[@]} -lt 2 ]]; then
  echo "# Error: expected at least 2 pods for shard 0, found ${chi_pods[@]} #"
  exit 1
fi
echo "#  Found Pods: ${chi_pods[@]} #"

# Create fresh table to use in simulation
echo -e "\n### Creating failure_sim table on each replica ###"
cat "$LAB_ROOT/sql/13_create_failure_sim_table.sql"
echo -e "\n"
for pod in "${chi_pods[@]}"; do
    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
        clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
        --multiquery < "$LAB_ROOT/sql/13_create_failure_sim_table.sql" \
        --format=PrettyCompact
done

# Print each replicas state before the crash
echo -e "\n### Printing BEFORE state on each pod (row counts + replication status) ###"
for pod in "${chi_pods[@]}"; do
    echo "# pod: $pod (BEFORE) #"

    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
        clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
        --multiquery < "$LAB_ROOT/sql/14_query_replica_health.sql" \
        --format=PrettyCompact
done

# Kill a replica
echo -e "\n### Deleting replica 1 pod: ${chi_pods[1]} ###"
kubectl delete pod ${chi_pods[1]} -n "$NAMESPACE"
echo "# Short wait for pod to terminate #"
sleep 3

# Insert into the alive replica and wait for operator to reconcile
echo -e "\n### Inserting data into replica 0: ${chi_pods[0]} ###"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i ${chi_pods[0]} -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/15_insert_during_failure.sql" \
    --format=PrettyCompact

echo -e "\n### Waiting 30 seconds for operator to recreate pod ###"
sleep 30

# Print each replicas state after the crash
echo -e "\n### Printing AFTER state on each pod (row counts + replication status) ###"
for pod in "${chi_pods[@]}"; do
    echo "# pod: $pod (AFTER) #"

    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
        clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
        --multiquery < "$LAB_ROOT/sql/14_query_replica_health.sql" \
        --format=PrettyCompact
done

echo -e "\n### Finished Simulation! ###"

# Cleanup the cluster for next simulation attempt
echo -e "\n### Preparing cluster for next simulation ###"
echo "# Dropping failure_sim and checking existence on each replica #"
for pod in "${chi_pods[@]}"; do
    echo "# $pod running reset script #"
    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
        clickhouse-client \
            --user="$CLICKHOUSE_USER" \
            --port="$CLICKHOUSE_TCP_PORT" \
            --multiquery < "$LAB_ROOT/sql/16_reset_fail_sim_table.sql" \
            --format=PrettyCompact
done

echo -e "\n### Reset complete. No failure_sim table should remain. ###"
