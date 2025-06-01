#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

delete_namespace_if_exists() {
    local ns="$1"

    echo "Checking for namespace: '$ns'"
    if kubectl get namespace "$ns" &> /dev/null; then
        echo "Deleting namespace: '$ns'"
        kubectl delete namespace "$ns"
        kubectl wait --for=delete namespace "$ns" --timeout=30s || echo "Warning: Namespace '$ns' not fully deleted after timeout."
    else
        echo "Namespace '$ns' not found. Nothing to delete."
    fi
}

delete_template_if_exists() {
    local path="$1"
    local response=$(kubectl delete -f "$path" --ignore-not-found)
    if [ -z "$response" ]; then
        echo "No resources deleted. Likely already gone."
    else
        echo "$response"
    fi
}

echo "Deleting Clickhouse Installation."
delete_template_if_exists "$LAB_ROOT/manifests/chi/clickhouse-installation.yaml"
echo "Deleting Clickhouse Keeper"
delete_template_if_exists "$LAB_ROOT/manifests/keeper/clickhouse-keeper.yaml"
echo "Deleting Altinity Clickhouse Operator."
delete_template_if_exists "$LAB_ROOT/manifests/operator/clickhouse-operator.yaml"

echo "Deleting namespaces:"
delete_namespace_if_exists "prometheus"
delete_namespace_if_exists "$OPERATOR_NAMESPACE"