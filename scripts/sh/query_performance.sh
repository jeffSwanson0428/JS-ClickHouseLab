#!/bin/bash
#set -e
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/env.sh"

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

echo -e "\n### Querying error counts per service from ${chi_pods[1]} ###"
cat "$LAB_ROOT/sql/07_query_errors_per_service.sql" 
echo -e "\n"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/07_query_errors_per_service.sql" \
    --format=PrettyCompact

echo -e "\n### Querying traffic per host ${chi_pods[1]} ###"
cat "$LAB_ROOT/sql/08_query_traffic_per_host.sql"
echo -e "\n"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/08_query_traffic_per_host.sql" \
    --format=PrettyCompact

echo -e "\n### Querying logs over time from ${chi_pods[1]} ###"
echo "#   Note: This query has a large output that has been surpressed to /dev/null #"
echo "#   To view its output, check the /deliverables/ directory #"
cat "$LAB_ROOT/sql/09_query_logs_over_time_by_hour.sql"
echo -e "\n"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/09_query_logs_over_time_by_hour.sql" >/dev/null 2>&1

# Enable query logging
echo "### Enabling Query Logging ###"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --query="SET log_queries = 1;"

echo -e "\n### Running slow query with logging enabled on ${chi_pods[1]} ###"
echo "#   Note: This query has a large output that has been surpressed to /dev/null #"
echo "#   To view its output, check the /deliverables/ directory #"
cat "$LAB_ROOT/sql/10_slow_query.sql"
echo -e "\n"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/10_slow_query.sql" >/dev/null 2>&1

echo -e "\n### Checking query_log for previous slow query on ${chi_pods[1]} ###"
cat "$LAB_ROOT/sql/11_query_system-query_log.sql"
echo -e "\n"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/11_query_system-query_log.sql" \
    --format=PrettyCompact
echo -e "\n# As we can see from the query_time, this is not the most snappy DML"

echo -e "\n### Explain slow query on ${chi_pods[1]} ###"
cat "$LAB_ROOT/sql/12_query_explain_slow_query.sql"
kubectl exec -n "$NAMESPACE" -c "$CLICKHOUSE_CHI_CONTAINER" -i "${chi_pods[1]}" -- \
    clickhouse-client --user="$CLICKHOUSE_USER" --port="$CLICKHOUSE_TCP_PORT" \
    --multiquery < "$LAB_ROOT/sql/12_query_explain_slow_query.sql"\
    --format=PrettyCompact
echo -e "\n# Analysis: This query is slow for several deliberate reasons: "
echo "# - It is iterating over every row. The WHERE clause does not utilize any of the columns in the tables index. "
echo "# - This forces it to read every row at least once. Clickhouse in unable to prune any data based on its known partition. " 
echo "# - It then executes several string functions across the columns in the select statement. "
echo "# - String functions must iterate of every byte within the data. "
echo "# - So for each row, the value stored in host, message, and timestamp must also be iterated over (sometimes multiple times). "
echo "# - Not only does this effect the CPU time, it also drastically increases the memory usage. "
echo "# - Lastly, the ORDER BY statement requires a sort across multiple fields that are different from the tables inherent ordering."
echo "# - This prevents clickhouse from using its pre-sorted data, and leads to slower sorting times. Likeny O(n log n) "

echo -e "\n# Suggested Changes: "
echo "# If we were to optimize for this query, we would need to make use of a materialized view. "
echo "# Creating a materialized view will prevent us from having to rewrite all of the ingested data. "
echo "# We could then create extra columns that account for the data that is modified by functions. "
echo "# lower(message) could then be inserted into a column named something like message_lower "
echo "# Likewise, reverse(host) can be inserted into the column rev_host "
echo "# This not only gives us the benefit of preprocessing the data outside of query runtime. "
echo "# We can also create a new ORDER BY to utilize these new columns to speed up sorting time "
echo "# ORDER BY (message_lower, rev_host) "
