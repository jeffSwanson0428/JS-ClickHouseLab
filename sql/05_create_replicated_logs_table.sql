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
