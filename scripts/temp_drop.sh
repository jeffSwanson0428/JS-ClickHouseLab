#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

SAMPLE_POD=$(
  kubectl get pods \
    -n "$NAMESPACE" \
    -l clickhouse.altinity.com/cluster \
    -o jsonpath='{.items[0].metadata.name}'
)

if [[ -z "$SAMPLE_POD" ]]; then
  echo "No ClickHouse pod found with label clickhouse.altinity.com/cluster in ns '$NAMESPACE'."
  echo "    Make sure your operator/CHI is up by running up.sh."
  exit 1
fi

CLUSTER=$(
  kubectl get pod "$SAMPLE_POD" \
    -n "$NAMESPACE" \
    -o jsonpath="{.metadata.labels['clickhouse\.altinity\.com/cluster']}"
)

echo "Detected ClickHouse cluster name:  $CLUSTER"

CLUSTER_PODS=(
  $(
    kubectl get pods \
      -n "$NAMESPACE" \
      -l "clickhouse.altinity.com/cluster=$CLUSTER" \
      -o jsonpath='{.items[*].metadata.name}'
  )
)

if [[ ${#CLUSTER_PODS[@]} -eq 0 ]]; then
  echo "No pods found for clickhouse.altinity.com/cluster=$CLUSTER"
  exit 1
fi

MAIN_POD="${CLUSTER_PODS[0]}"

TABLE_NAME="test_replication"
echo "Dropping table '$TABLE_NAME' ON CLUSTER '$CLUSTER' …"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CONTAINER" -i "$MAIN_POD" -- \
  clickhouse-client \
    --user="$CLICKHOUSE_USER" \
    --port="$CLICKHOUSE_PORT" \
    --query "DROP TABLE IF EXISTS default.$TABLE_NAME ON CLUSTER '$CLUSTER';"


# ZK_BASE="/clickhouse"
# echo "Removing ZooKeeper znodes under '$ZK_BASE/tables/$CLUSTER/$TABLE_NAME' and '$ZK_BASE/replicas/$CLUSTER/$TABLE_NAME' …"
# kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CONTAINER" -i "$MAIN_POD" -- \
#   clickhouse-keeper-client -q "rmr $ZK_BASE/tables/$CLUSTER/$TABLE_NAME" 2>/dev/null || true

# kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CONTAINER" -i "$MAIN_POD" -- \
#   clickhouse-keeper-client -q "rm
