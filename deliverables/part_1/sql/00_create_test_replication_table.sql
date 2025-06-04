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
