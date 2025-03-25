# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Log Analytics Workspace (for monitoring)
resource "azurerm_log_analytics_workspace" "law" {
  name                = "bank-log-analytics"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
}

# Container App Environment (shared by both apps)
resource "azurerm_container_app_environment" "cae" {
  name                       = var.container_app_env_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# Storage Account for persistence
resource "azurerm_storage_account" "storage" {
  name                     = "bankstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Storage Shares for Postgres and Redis
resource "azurerm_storage_share" "postgres_share" {
  name                 = "postgres-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 50  # Size in GB
}

resource "azurerm_storage_share" "redis_share" {
  name                 = "redis-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 10  # Size in GB
}

# Postgres Container App
resource "azurerm_container_app" "postgres_app" {
  name                         = var.postgres_app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"

  template {
    container {
      name   = "postgres"
      image  = "pgvector/pgvector:0.8.0-pg17"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "POSTGRES_USER"
        value = "bank_user"
      }
      env {
        name  = "POSTGRES_PASSWORD"
        value = var.postgres_password
      }
      env {
        name  = "POSTGRES_DB"
        value = "bank_recommendations"
      }

      volume_mount {
        name       = "postgres-data"
        mount_path = "/var/lib/postgresql/data"
      }
    }

    volume {
      name         = "postgres-data"
      storage_type = "AzureFile"
      storage_name = azurerm_storage_share.postgres_share.name
      storage_account_name = azurerm_storage_account.storage.name
      storage_account_key  = azurerm_storage_account.storage.primary_access_key
    }

    min_replicas = 0  # Scale to zero when idle
    max_replicas = 2  # Max instances when busy
  }

  ingress {
    external_enabled = true
    target_port      = var.postgres_port  # 5432
    transport        = "tcp"
    traffic_weight {
      percentage = 100
    }
  }
}

# Redis Container App
resource "azurerm_container_app" "redis_app" {
  name                         = var.redis_app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"

  template {
    container {
      name   = "redis"
      image  = "redis:7"
      cpu    = 0.25
      memory = "0.5Gi"
      command = ["redis-server", "--appendonly", "yes"]  # Enable AOF persistence
      volume_mount {
        name       = "redis-data"
        mount_path = "/data"
      }
      readiness_probe {
        transport = "TCP"
        port      = 6379
      }
      liveness_probe {
        transport = "TCP"
        port      = 6379
      }
    }

    volume {
      name         = "redis-data"
      storage_type = "AzureFile"
      storage_name = azurerm_storage_share.redis_share.name
      storage_account_name = azurerm_storage_account.storage.name
      storage_account_key  = azurerm_storage_account.storage.primary_access_key
    }

    min_replicas = 0  # Scale to zero when idle
    max_replicas = 2  # Max instances when busy
  }

  ingress {
    external_enabled = true
    target_port      = var.redis_port  # 6379
    transport        = "tcp"
    traffic_weight {
      percentage = 100
    }
  }
}