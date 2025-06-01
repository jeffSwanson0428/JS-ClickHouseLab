#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Check for envsubst
if ! command -v envsubst &> /dev/null; then
    echo "'envsubst' not found. Please install gettext with 'brew install gettext && brew link --force gettext'"
    exit 1
fi

echo "Creating namespaces:"
kubectl create namespace "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "prometheus" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating Altinity Clickhouse Operator"
envsubst < $LAB_ROOT/manifests/operator/clickhouse-operator-template.yaml > $LAB_ROOT/manifests/operator/clickhouse-operator.yaml
kubectl apply -f $LAB_ROOT/manifests/operator/clickhouse-operator.yaml

echo "Creating Clickhouse Keeper"
kubectl apply -f $LAB_ROOT/manifests/keeper/clickhouse-keeper.yaml

echo "Creating Clickhouse Installation"
kubectl apply -f $LAB_ROOT/manifests/chi/clickhouse-installation.yaml
