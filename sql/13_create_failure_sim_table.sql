CREATE TABLE IF NOT EXISTS failure_sim ON CLUSTER '{cluster}'
(
    event_id UInt64,
    event_time DateTime
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/failure_sim',
    '{replica}'
)
ORDER BY (event_id);
