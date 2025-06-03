#!/bin/bash

# Retrieve and store the absolute path for the lab root directory 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LAB_ROOT=$PROJECT_ROOT

# Required for clickhouse-operator manifest
export OPERATOR_NAMESPACE=clickhouse-lab
export OPERATOR_IMAGE=altinity/clickhouse-operator:latest
export OPERATOR_IMAGE_PULL_POLICY=IfNotPresent
export METRICS_EXPORTER_IMAGE=altinity/metrics-exporter:latest
export METRICS_EXPORTER_IMAGE_PULL_POLICY=IfNotPresent

# Useful variables for kubectl, clickhouse-client, etc.
export NAMESPACE=clickhouse-lab
export CLICKHOUSE_CHI_CONTAINER=clickhouse
export CLICKHOUSE_KEEPER_CONTAINER=clickhouse-keeper
export CLICKHOUSE_TCP_PORT=9000

export CLICKHOUSE_HOST="localhost"
export CLICKHOUSE_HTTP_PORT=8123
export CLICKHOUSE_USER=default
export CLICKHOUSE_PASSWORD=""
export CLICKHOUSE_DATABASE="default"
export CLICKHOUSE_TABLE="logs"