#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

PODS=(
    $( kubectl get pods \
     -n "clickhouse-lab" \
     -l "clickhouse.altinity.com/cluster=cluster-1,clickhouse.altinity.com/shard=0" \
     -o jsonpath='{.items[*].metadata.name}' ) \
)

if [[ -z "$PODS" ]]; then
    echo "No pods found. Ensure the environment is up by running up.sh"
    exit 1
fi

echo "Creating replicated test table across both replicas on shard 0"
for POD in "${PODS[@]}"; do
    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CONTAINER" -i "$POD" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/00_create_test_replication_table.sql"
done

echo "Inserting into table on node ${PODS[0]}"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CONTAINER" -i "${PODS[0]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/01_insert_into_one_node.sql"

echo "Querying table from ${PODS[1]}"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CONTAINER" -i "${PODS[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_PORT" \
    --multiquery < "$LAB_ROOT/sql/02_query_from_other_node.sql" 
