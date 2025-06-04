# Part 3: Query Performance & Troubleshooting

This section includes 1 script: `/scripts/sh/query_performance.sh`, which:

- Retrieves a pod from each replica  
- Executes several queries against the `logs` table with 1,000,000 records:
  - Error counts per service  
  - Traffic per host  
  - Logs over time  
    - Output too long to include in the script; view in `part_3/logs/` directory for a separate output file
- Enables query logging  
- Executes a "slow" query  
- Queries `query_log` for the slow query  
- Executes `EXPLAIN` on the slow query  
- Analyzes why the query is slow  
- Makes suggestions for ClickHouse tuning  

---
### Querying Error Counts per Service

```sql
SELECT
    service_name AS service,
    count() AS total_errors
FROM
    logs
PREWHERE
    log_level = 'Error'
GROUP BY 
    service_name
;
```

```
┌─service─────────────────┬─total_errors─┐
│ billing                 │        18204 │
│ identity                │        18057 │
│ delivery-manager        │        18212 │
│ auth-service            │        18001 │
│ order_processor         │        18113 │
│ analytics-engine        │        17995 │
│ session_manager         │        18071 │
│ cdn-edge-node           │        18523 │
│ client-billing-database │        18071 │
│ log-streaming-operator  │        18060 │
│ log-streaming-manager   │        18115 │
└─────────────────────────┴──────────────┘
```

---

### Querying Traffic per Host

```sql
SELECT
    host,
    count()
FROM
    logs
GROUP BY
    host
;
```

```
┌─host─────────────────────────────┬─count()─┐
│ laptop-45.miller-black.com       │   32429 │
│ email-94.orr-contreras.com       │   32150 │
│ laptop-39.brown-nelson.net       │   32182 │
│ desktop-69.gonzalez-kirk.org     │   32030 │
│ db-39.ramirez-kennedy.com        │   32448 │
│ desktop-77.johnson-gomez.com     │   32194 │
│ desktop-63.jackson-patrick.info  │   32179 │
│ email-89.baird-mercado.info      │   31991 │
│ lt-63.rosales-meadows.info       │   32166 │
│ laptop-74.jenkins-weber.com      │   32282 │
│ email-83.carter-reyes.com        │   32569 │
│ email-48.wagner-mcclain.com      │   32039 │
│ srv-56.jackson-washington.com    │   32180 │
│ desktop-46.cordova-hamilton.com  │   31957 │
│ srv-31.cunningham-rodriguez.com  │   32289 │
│ email-28.clark-watkins.com       │   32426 │
│ srv-60.kennedy-andrews.com       │   32515 │
│ laptop-85.turner-daniel.info     │   32406 │
│ email-29.hill-little.info        │   32268 │
│ laptop-63.pena-spencer.com       │   31984 │
│ email-05.hernandez-anderson.com  │   32153 │
│ srv-67.morris-edwards.com        │   32679 │
│ web-32.harris-griffin.com        │   32434 │
│ email-33.orozco-walters.com      │   32560 │
│ desktop-71.thomas-anderson.info  │   32104 │
│ lt-13.chavez-phillips.com        │   32075 │
│ desktop-34.gonzalez-thompson.net │   32058 │
│ lt-11.gallagher-palmer.com       │   32026 │
│ desktop-51.turner-black.net      │   32490 │
│ email-24.gonzalez-hawkins.com    │   32358 │
│ laptop-33.gonzalez-cox.net       │   32379 │
└──────────────────────────────────┴─────────┘
```

---

### Querying Logs Over Time

```sql
SELECT
    toStartOfHour(timestamp) AS date_to_hour,
    count() AS logs_count
FROM 
    logs
GROUP BY
    date_to_hour
ORDER BY
    date_to_hour
;
```

```
# Note: Output suppressed to /dev/null.
# View full results in /deliverables/part_3/logs/
```

---

### Enabling Query Logging

```
### Enabling Query Logging ###
SET log_queries = 1;
```

---

### Running Slow Query

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
LIMIT 1000000
;
```

```
# Note: Output suppressed to /dev/null.
```

---

### Querying `system.query_log` for the Slow Query

```sql
SELECT 
    query_start_time,
    query_duration_ms,
    read_rows,
    read_bytes,
    memory_usage,
    result_rows,
    result_bytes,
    query
FROM
    system.query_log
WHERE 
    type = 'QueryFinish'
    AND query ILIKE '%length(message)%lower(message)%LIMIT 1000000%'
ORDER BY
    event_time DESC 
LIMIT 1
;
```

```
# As we can see from the query_time, this is not the most snappy query
```

---

### Explain Plan for the Slow Query

```sql
EXPLAIN SELECT
    host,
    length(message),
    lower(message),
    reverse(host),
    toUnixTimestamp(timestamp)
FROM logs
WHERE log_level != ''
ORDER BY
    lower(message),
    reverse(host),
    toUnixTimestamp(timestamp)
LIMIT 1000000
;
```

```
┌─explain────────────────────────────────────────────────────────────────────────┐
│ Expression ((Project names + (Before ORDER BY + Projection) [lifted up part])) │
│   Limit (preliminary LIMIT (without OFFSET))                                   │
│     Sorting (Sorting for ORDER BY)                                             │
│       Expression ((Before ORDER BY + Projection))                              │
│         Expression                                                             │
│           ReadFromMergeTree (default.logs)                                     │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## Query Performance Analysis

```
This query is slow for several deliberate reasons:
- It is iterating over every row. The WHERE clause does not utilize any of the columns in the table's index.
- This forces ClickHouse to read every row.
- ClickHouse cannot prune partitions based on the WHERE clause.
- The query applies multiple string functions (e.g., `lower()`, `reverse()`) to every row.
- These functions are CPU-intensive and memory-heavy.
- The ORDER BY clause does not align with the table’s native sort order.
- As a result, the engine performs a full sort (likely O(n log n)).
```

---

## Suggested Optimizations

``` 
- If we were to optimize for this query, we would need to make use of a materialized view. 
- Creating a materialized view will prevent us from having to rewrite all of the ingested data. 
- We could then create extra columns that account for the data that is modified by functions. 
- lower(message) could then be inserted into a column named something like message_lower 
- Likewise, reverse(host) can be inserted into the column rev_host 
- This not only gives us the benefit of preprocessing the data outside of query runtime. 
- We can also create a new ORDER BY to utilize these new columns to speed up sorting time 
    - ORDER BY (message_lower, rev_host) 
```
