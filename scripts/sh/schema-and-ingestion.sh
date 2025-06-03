#!/bin/bash
set -e
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/env.sh"


# Retrieve pod from each replica
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

echo -e "\n### Creating replicated test table across both replicas ###"
cat "$LAB_ROOT/sql/05_create_replicateD_logs_table.sql"
for pod in "${chi_pods[@]}"; do
    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/05_create_replicateD_logs_table.sql"
done

echo -e "\n"
echo "#########################################"
echo "###     Ingest 1M Synthetic Logs?     ###"
echo "#########################################"
while true; do
    read -r -p "### Proceed with ingestion? [y/n]: " answer
    case "$answer" in
        [Yy])
            # Port forward the http port on the cluster CHI service
            # Required to execute ingestion script in local shell against k8s hosted clickhouse
            echo "### Port-forwarding the cluster CHI service http port ###"
            kubectl port-forward -n clickhouse-lab svc/clickhouse-altinity-demo 8123:8123 >/dev/null 2>&1 & 
            PF_PID=$!
            # Short sleep to ensure portforward connects
            sleep 5

            # Begin Ingestion
            echo -e "\n### Inserting synthetic logs via Python script ###"
            python3 $LAB_ROOT/scripts/py/generate_and_ingest_synthetic_logs.py \
                --host "$CLICKHOUSE_HOST" \
                --port "$CLICKHOUSE_HTTP_PORT" \
                --username "$CLICKHOUSE_USER" \
                --password "$CLICKHOUSE_PASSWORD" \
                --database "$CLICKHOUSE_DATABASE" \
                --table "$CLICKHOUSE_TABLE"

            echo -e "\n### Killing port-forward process ###"
            kill $PF_PID
            # Short sleep to ensure portforward is killed
            sleep 5
            if [ $? -eq 0 ]; then
                echo "# Port-forward process (PID $PF_PID) successfully terminated. #"
            else
                echo "# Warning: Port-forward process (PID $PF_PID) was not found or already terminated. #"
            fi

            break
            ;;
        [Nn])
            break
            ;;
        *)
            echo "### Please enter y or n. ###"
            ;;
    esac
done

echo -e "\n### Counting records stored on pods from each replica ###"
cat "$LAB_ROOT/sql/06_count_logs_records.sql"
for pod in "${chi_pods[@]}"; do
    echo -n "$pod: total records = "
    kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "$pod" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/06_count_logs_records.sql"
done
