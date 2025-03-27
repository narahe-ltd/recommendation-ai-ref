  
# pre-seed

## 1. apply storage
  terraform apply -target=azurerm_storage_account.storage -target=azurerm_storage_share.postgres_share

  az storage file upload \
  --account-name "bankstorage${var.resource_group_name}" \
  --account-key "$(az storage account keys list --resource-group ${var.resource_group_name} --account-name "bankstorage${var.resource_group_name}" --query '[0].value' -o tsv)" \
  --share-name postgres-data \
  --source ./pgdata.zip \
  --path pgdata.zip

## 2. test key
  az storage account keys list --resource-group bankrg --account-name "bankstoragebankrg" --query '[0].value' -o tsv

## 3. update with resource_group_name wiht bankrg
  az storage file upload \
  --account-name "bankstoragebankrg" \
  --account-key "$(az storage account keys list --resource-group bankrg --account-name "bankstoragebankrg" --query '[0].value' -o tsv)" \
  --share-name postgres-data \
  --source ./pgdata.zip \
  --path pgdata.zip

## 4. verify
    az containerapp logs show --name ${var.postgres_app_name} --resource-group ${var.resource_group_name}
  
    az containerapp logs show --name bank-postgres-app --resource-group bankrg


# here ref

## Steps
Run PostgreSQL Locally to Initialize the Data Directory:
Start a temporary PostgreSQL container with the same environment variables as your postgres_app:
bash

Collapse

Wrap

Copy
docker run -d --name postgres-init \
  -e POSTGRES_USER=bank_user \
  -e POSTGRES_PASSWORD=<your_postgres_password> \
  -e POSTGRES_DB=bank_recommendations \
  -e PGDATA=/var/lib/postpostgresql/data/pgdata \
  pgvector/pgvector:0.8.0-pg17
Replace <your_postgres_password> with the value of var.postgres_password from your terraform.tfvars or environment.
Wait for initialization to complete (usually a few seconds). Check the logs:
bash

Collapse

Wrap

Copy
docker logs postgres-init
Look for database system is ready to accept connections to confirm it’s ready.
Extract the Initialized Data Directory:
Copy the pgdata directory from the container to your local machine:
bash

Collapse

Wrap

Copy
docker cp postgres-init:/var/lib/postgresql/data/pgdata ./pgdata
Stop and remove the temporary container:
bash

Collapse

Wrap

Copy
docker stop postgres-init
docker rm postgres-init
You should now have a local ./pgdata directory containing files like postgresql.conf, base/, and pg_wal/.
Upload the Data to the Azure File Share:
Ensure your storage account (bankstorage${var.resource_group_name}) and file share (postgres-data) exist. If not, deploy the Terraform config up to the storage resources first:
bash

Collapse

Wrap

Copy
terraform apply -target=azurerm_storage_account.storage -target=azurerm_storage_share.postgres_share
Upload the pgdata contents to the postgres-data share using the Azure CLI:
bash

Collapse

Wrap

Copy
az storage file upload-batch \
  --account-name "bankstorage${var.resource_group_name}" \
  --account-key "$(az storage account keys list --resource-group ${var.resource_group_name} --account-name "bankstorage${var.resource_group_name}" --query '[0].value' -o tsv)" \
  --source ./pgdata \
  --destination postgres-data
Replace ${var.resource_group_name} with your actual resource group name (e.g., my-bank-rg).
Verify the upload in the Azure Portal under Storage Accounts > bankstorage${var.resource_group_name} > File Shares > postgres-data. You should see the pgdata directory and its contents.
Deploy the Full Configuration:
With the postgres-data share pre-seeded, deploy the complete Terraform configuration:
bash

Collapse

Wrap

Copy
./setup.sh
The postgres_app will start using the pre-seeded data without running initdb, avoiding the Operation not permitted error.
Verify:
Check the container logs to ensure PostgreSQL starts correctly:
bash

Collapse

Wrap

Copy
az containerapp logs show --name ${var.postgres_app_name} --resource-group ${var.resource_group_name}
Look for database system was shut down at ... and database system is ready to accept connections, indicating it’s using the existing data.
Test a redeploy (e.g., change cpu = 0.75 and run ./setup.sh again) to confirm it reuses the data without issues.