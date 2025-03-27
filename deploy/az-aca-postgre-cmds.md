az group create \
  --name myResourceGroup \
  --location eastus

az storage account create \
  --name sdrhmstoragaccount01 \
  --resource-group myResourceGroup \
  --location eastus \
  --sku Standard_LRS

STORAGE_KEY=$(az storage account keys list \
  --resource-group myResourceGroup \
  --account-name sdrhmstoragaccount01 \
  --query "[0].value" -o tsv)

az storage share create \
  --account-name sdrhmstoragaccount01 \
  --account-key "$STORAGE_KEY" \
  --name myfileshare

az containerapp env create \
  --name myContainerAppEnv \
  --resource-group myResourceGroup \
  --location eastus

az containerapp create \
  --name my-postgres-app \
  --resource-group myResourceGroup \
  --environment myContainerAppEnv \
  --image postgres:latest \
  --secrets "postgres-password=mysecretpassword" \
  --env-vars "POSTGRES_USER=myuser" "POSTGRES_PASSWORD=secretref:postgres-password" "POSTGRES_DB=mydb" "PGDATA=/var/lib/postgresql/data/pgdata" \
  --cpu 0.5 \
  --memory 1.0Gi \
  --min-replicas 1 \
  --max-replicas 1 \
  --ingress internal \
  --target-port 5432 \
  --transport tcp \
  --volume-mounts "postgres-storage:/var/lib/postgresql/data" \
  --volume "postgres-storage:azure-files-volume:sdrhmstoragaccount01:myfileshare:$STORAGE_KEY"

az containerapp create \
  --name my-postgres-app \
  --resource-group myResourceGroup \
  --environment myContainerAppEnv \
  --image postgres:latest \
  --secrets "postgres-password=mysecretpassword" \
  --env-vars "POSTGRES_USER=myuser" "POSTGRES_PASSWORD=secretref:postgres-password" "POSTGRES_DB=mydb" "PGDATA=/var/lib/postgresql/data/pgdata" \
  --cpu 0.5 \
  --memory 1.0Gi \
  --min-replicas 1 \
  --max-replicas 1 \
  --ingress internal \
  --target-port 5432 \
  --transport tcp \
  --volume-mounts "postgres-storage:/var/lib/postgresql/data" \
  --volume "postgres-storage:azure-files-volume:sdrhmstoragaccount01:myfileshare:secrect"

  # delete all

  # Delete Container App
az containerapp delete --name my-postgres-app --resource-group myResourceGroup --yes

# Delete Environment (if not shared)
az containerapp env delete --name myContainerAppEnv --resource-group myResourceGroup --yes

# Delete File Share
az storage share delete --account-name sdrhmstoragaccount01 --name myfileshare --account-key "$STORAGE_KEY" --yes

# Delete Storage Account
az storage account delete --name sdrhmstoragaccount01 --resource-group myResourceGroup --yes

# Delete Resource Group (all resources)
az group delete --name myResourceGroup --yes