#!/bin/bash
# Setup script for bank-recommendation-system Azure infrastructure
# Use this to deploy resources when needed

set -e

# Navigate to the terraform directory
cd "$(dirname "$0")/tf"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Validate the configuration
echo "Validating Terraform configuration..."
terraform validate

# Plan the deployment
echo "Planning deployment..."
terraform plan -out=tfplan

echo "Review the plan above."
read -p "Continue with deployment? (y/n): " confirm

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

echo -e "\nTo destroy these resources when not in use, run: ./teardown.sh" 