#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Create the K8s infra (Namespaces, Operator, CHI, Clickhouse-Keeper)
echo "#########################################"
echo "###     Would you like to deploy      ###"
echo "###  the kubernetes infrasctructure?  ###"
echo "#########################################"
while true; do
  read -r -p "### Proceed with deployment? [y/n]: " answer
  case "$answer" in
    [Yy]) 
      echo "### Deploying infrastructure..."
      bash "$LAB_ROOT/scripts/sh/up.sh"
      # Ideally I would use an IaC tool like pulumi to avoid this nonsense.
      echo -e "### Sleeping for 3 minutes to allow pods to come up (Sorry!) ###\n"
      sleep 180
      break
      ;;
    [Nn])
      echo -e "### Skipping deployment. ###\n"
      break
      ;;
    *)
      echo "### Please enter y or n. ###"
      ;;
  esac
done

# Confirm replication and clickhouse-keeper health through several means including:
# Creating replicated table, inserting on 1 replica and querying on the other
# Verifying system.parts validates the inserts happened across all nodes
# Getting Clickhouse-Keeper pods for status
# Validating zNodes are created on Clickhouse-Keeper for each CHI node
# Validating system.replicas shows the same replication data across all CHI nodes
echo "#########################################"
echo "###       Validate replication        ###"
echo "###   and Clickhouse-Keeper health?   ###"
echo "#########################################"
while true; do
    read -r -p "### Proceed with validation? [y/n]: " answer
    case "$answer" in
        [Yy])
            echo "### Validating replication and keeper health. ###"
            bash "$LAB_ROOT/scripts/sh/test-replication-and-health.sh"
            break
            ;;
        [Nn])
            break
            ;;
        *)
            echo "### Please enter y or n. ###"
            ;;
    esac
done



# Create schema and ingest synthetic data
echo -e "\n"
echo "#########################################"
echo "###   Create schema for logs table?   ###"
echo "#########################################"
while true; do
    read -r -p "### Proceed with schema creation? [y/n]: " answer
    case "$answer" in
        [Yy])
            echo "### Beginning Schema deployment and data ingestion ###"
            bash "$LAB_ROOT/scripts/sh/schema-and-ingestion.sh"
            break
            ;;
        [Nn])
            break
            ;;
        *)
            echo "### Please enter y or n. ###"
            ;;
    esac
done

# Execute required querys and evaluate their performance.
echo "#########################################"
echo "###    Execute queries against the    ###"
echo "###        synthetic log data?        ###"
echo "#########################################"
while true; do
  read -r -p "### Proceed with queries? [y/n]: " answer
  case "$answer" in
    [Yy]) 
      echo "### Deploying infrastructure..."
      bash "$LAB_ROOT/scripts/sh/query_performance.sh"
      break
      ;;
    [Nn])
      echo -e "### Skipping. ###\n"
      break
      ;;
    *)
      echo "### Please enter y or n. ###"
      ;;
  esac
done

echo -e "\n"
echo "#########################################"
echo "###      The demo has concluded.      ###"
echo "###      Thank you for viewing!       ###"
echo "#########################################"
while true; do
    read -r -p "Destroy all Kubernetes objects? Press 'y' to continue: " confirm
    if [[ "$confirm" == "y" ]]; then
        break
    fi
done
bash "$LAB_ROOT/scripts/sh/down.sh"
