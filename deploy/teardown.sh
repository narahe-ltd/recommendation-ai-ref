#!/bin/bash
# Teardown script for bank-recommendation-system Azure infrastructure
# Use this to completely destroy resources when not in use to save costs

set -e

echo "WARNING: This will destroy all resources in the bank-rg resource group."
echo "This action cannot be undone. All data will be lost."
read -p "Are you sure you want to continue? (y/n): " confirm

if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo "Teardown cancelled."
    exit 0
fi


export SubscriptionId=$(az account show --query id -o tsv)
export ARM_SUBSCRIPTION_ID=$SubscriptionId


# Navigate to the terraform directory
cd "$(dirname "$0")/tf"

# Initialize Terraform (in case it hasn't been initialized)
terraform init

# Destroy all resources
echo "Destroying all resources..."
terraform destroy -auto-approve

echo "Teardown complete. All resources have been destroyed."
echo "To redeploy, run: cd tf && terraform apply" 