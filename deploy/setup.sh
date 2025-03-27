#!/bin/bash
# Setup script for bank-recommendation-system Azure infrastructure
# Use this to deploy either backend or app resources based on parameter
# Usage: ./setup.sh [backend|app] (defaults to app)

set -e

# Determine which component to deploy (default to 'app')
COMPONENT="${1:-app}"

export SubscriptionId=$(az account show --query id -o tsv)
export ARM_SUBSCRIPTION_ID=$SubscriptionId

# Validate the component parameter
if [[ "$COMPONENT" != "backend" && "$COMPONENT" != "app" ]]; then
    echo "Error: Invalid parameter. Use 'backend' or 'app'."
    echo "Usage: $0 [backend|app]"
    exit 1
fi

# Set the target directory based on component
if [[ "$COMPONENT" == "backend" ]]; then
    TARGET_DIR="$(dirname "$0")/tf-backend"
    echo "Deploying backend infrastructure..."
else
    TARGET_DIR="$(dirname "$0")/tf"
    echo "Deploying application infrastructure..."
fi

# Navigate to the target directory
cd "$TARGET_DIR"

# Backend configuration for app deployment (only used if deploying app)
if [[ "$COMPONENT" == "app" ]]; then
    BACKEND_RG=${BACKEND_RG:-"terraform-backend-rg"}
    BACKEND_STORAGE=${BACKEND_STORAGE:-"tfbackend07pj1xf2"}  # Replace <randomsuffix> with actual value
    BACKEND_CONTAINER=${BACKEND_CONTAINER:-"tfstate"}
    BACKEND_KEY=${BACKEND_KEY:-"bank-recommendation-system.tfstate"}

    # Initialize Terraform with remote backend for app
    echo "Initializing Terraform with remote backend..."
    terraform init \
        -backend-config="resource_group_name=$BACKEND_RG" \
        -backend-config="storage_account_name=$BACKEND_STORAGE" \
        -backend-config="container_name=$BACKEND_CONTAINER" \
        -backend-config="key=$BACKEND_KEY" \
        -reconfigure
else
    # Initialize Terraform without backend config for backend deployment
    echo "Initializing Terraform..."
    terraform init
fi

# Validate the configuration
echo "Validating Terraform configuration..."
terraform validate

# Plan the deployment
echo "Planning deployment..."
terraform plan -out=tfplan

echo "Review the plan above."
read -t 5 -p "Continue with deployment? (y/n): " confirm || confirm="y"
if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Apply the configuration
echo "Deploying resources..."
terraform apply tfplan

echo "Deployment complete!"
echo "Connection information:"
terraform output

if [[ "$COMPONENT" == "app" ]]; then
    echo -e "\nTo destroy these resources when not in use, run: ./teardown.sh"
else
    echo -e "\nBackend deployment complete. Use the outputs to configure your app deployment."
fi