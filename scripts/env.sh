#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export LAB_ROOT=$PROJECT_ROOT
export NAMESPACE=clickhouse-lab
export OPERATOR_IMAGE=altinity/clickhouse-operator:latest
export OPERATOR_IMAGE_PULL_POLICY=IfNotPresent
export METRICS_EXPORTER_IMAGE=altinity/metrics-exporter:latest
export METRICS_EXPORTER_IMAGE_PULL_POLICY=IfNotPresent

export CLICKHOUSE_CONTAINER=clickhouse
export CLICKHOUSE_USER=default
export CLICKHOUSE_PORT=9000