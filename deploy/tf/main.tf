# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "bank-recommendations-rg"
  location = var.location
}

# Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "law" {
  name                = "bank-recommendations-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Azure Container Apps Environment
resource "azurerm_container_app_environment" "aca_env" {
  name                       = "bank-recommendations-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# Azure File Share for persistent storage
resource "azurerm_storage_account" "storage" {
  name                     = "bankrecstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "postgres_share" {
  name                 = "postgres-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 50 # Size in GB
}

resource "azurerm_storage_share" "redis_share" {
  name                 = "redis-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 50 # Size in GB
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Postgres Container App
resource "azurerm_container_app" "postgres" {
  name                         = "postgres-app"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  ingress {
    external_enabled = true
    target_port      = 5432
    traffic_weight {
      percentage = 100
    }
  }

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
        value = "secure_password_123"
      }
      env {
        name  = "POSTGRES_DB"
        value = "bank_recommendations"
      }

      volume_mounts {
        name = "postgres-data"
        path = "/var/lib/postgresql/data"
      }

      readiness_probe {
        transport = "TCP"
        port      = 5432
      }
      liveness_probe {
        transport = "TCP"
        port      = 5432
      }
    }

    volume {
      name         = "postgres-data"
      storage_name = azurerm_storage_share.postgres_share.name
      storage_type = "AzureFile"
    }
  }
}

# Redis Container App
resource "azurerm_container_app" "redis" {
  name                         = "redis-app"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  template {
    container {
      name   = "redis"
      image  = "redis:7"
      cpu    = 0.25
      memory = "0.5Gi"

      volume_mounts {
        name = "redis-data"
        path = "/data"
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
      storage_name = azurerm_storage_share.redis_share.name
      storage_type = "AzureFile"
    }
  }
}
