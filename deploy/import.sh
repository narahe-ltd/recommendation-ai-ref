#!/bin/bash
# Import script for bank-recommendation-system Azure infrastructure
# This script imports existing resources into the Terraform state

set -e

# Navigate to the terraform directory
cd "$(dirname "$0")/tf"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Import the Container App Environment
echo "Importing existing Container App Environment..."
terraform import azurerm_container_app_environment.cae \
  "/subscriptions/dfe4f19e-0de2-45f1-b1e7-f1aa89766598/resourceGroups/bank-rg/providers/Microsoft.App/managedEnvironments/bank-ca-env"

echo "Import complete!"
echo "You can now run ./setup.sh again to continue the deployment." 