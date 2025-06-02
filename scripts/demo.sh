#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Create the K8s infra (Namespaces, Operator, CHI, Clickhouse-Keeper)
bash "$LAB_ROOT/scripts/up.sh"
# Confirm replication and clickhouse-keeper health through several means including:
# Creating replicated table, inserting on 1 replica and querying on the other
# Verifying system.parts validates the inserts happened across all nodes
# Getting Clickhouse-Keeper pods for status
# Validating zNodes are created on Clickhouse-Keeper for each CHI node
# Validating system.replicas shows the same replication data across all CHI nodes
bash "$LAB_ROOT/scripts/test-replication-and-health.sh"

echo "######## The demo has concluded. ########"
echo "#######  Thank you for viewing!   #######"
while true; do
  read -r -p "Destroy all Kubernetes objects? Press 'y' to continue: " confirm
  if [[ "$confirm" == "y" ]]; then
    break
  fi
done
bash "$LAB_ROOT/scripts/down.sh"
