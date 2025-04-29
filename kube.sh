#!/bin/bash

# Define friendly cluster names and corresponding kubeconfig paths (must match in order)
CLUSTER_NAMES=("dev-cluster" "test-cluster" "stage-cluster" "prod-cluster" "dr-cluster")
KUBECONFIG_FILES=(
    "/path/to/kubeconfig-dev.yaml"
    "/path/to/kubeconfig-test.yaml"
    "/path/to/kubeconfig-stage.yaml"
    "/path/to/kubeconfig-prod.yaml"
    "/path/to/kubeconfig-dr.yaml"
)

# Show available cluster names
echo "Available clusters:"
for name in "${CLUSTER_NAMES[@]}"; do
    echo "- $name"
done

# Prompt user to enter a cluster name
read -p "Enter the name of the cluster you want to connect to: " cluster_input

# Find matching cluster
found=false
for i in "${!CLUSTER_NAMES[@]}"; do
    if [[ "$cluster_input" == "${CLUSTER_NAMES[$i]}" ]]; then
        export KUBECONFIG="${KUBECONFIG_FILES[$i]}"
        echo "Switched to ${CLUSTER_NAMES[$i]} using kubeconfig: ${KUBECONFIG_FILES[$i]}"
        kubectl config get-contexts
        found=true
        break
    fi
done

# Handle invalid input
if [ "$found" = false ]; then
    echo "Cluster name not recognized. Exiting."
    exit 1
fi
