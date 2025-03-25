# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "bank-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# Subnet for Container Apps
resource "azurerm_subnet" "container_apps" {
  name                 = "container-apps-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  delegation {
    name = "container-apps-delegation"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Log Analytics Workspace (for monitoring)
resource "azurerm_log_analytics_workspace" "law" {
  name                = "bank-log-analytics"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Container App Environment (shared by both apps)
resource "azurerm_container_app_environment" "cae" {
  name                       = var.container_app_env_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id
  tags                       = var.tags
}

# Storage Account for persistence
resource "azurerm_storage_account" "storage" {
  name                     = "bankstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = "LRS"
  min_tls_version         = "TLS1_2"
  tags                     = var.tags
}

# Enable blob encryption for storage account
data "azurerm_storage_account_sas" "storage_sas" {
  connection_string = azurerm_storage_account.storage.primary_connection_string
  https_only       = true
  signed_version   = "2020-08-04"
  
  start  = "2023-01-01"
  expiry = "2024-12-31"
  
  services {
    blob  = true
    queue = false
    table = false
    file  = true
  }
  
  resource_types {
    service   = true
    container = true
    object    = true
  }
  
  permissions {
    read    = true
    write   = true
    delete  = false
    list    = true
    add     = true
    create  = true
    update  = true
    process = false
    tag     = false
    filter  = false
  }
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
  quota                = var.postgres_storage_quota
}

resource "azurerm_storage_share" "redis_share" {
  name                 = "redis-data"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = var.redis_storage_quota
}

# Network Security Group for PostgreSQL
resource "azurerm_network_security_group" "postgres_nsg" {
  name                = "postgres-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "allow-postgres"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = var.postgres_port
    source_address_prefix     = "*"  # Allow from anywhere (you can restrict this to your IP)
    destination_address_prefix = "*"
  }
}

# Network Security Group for Redis
resource "azurerm_network_security_group" "redis_nsg" {
  name                = "redis-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "allow-redis"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = var.redis_port
    source_address_prefix     = "*"  # Allow from anywhere (you can restrict this to your IP)
    destination_address_prefix = "*"
  }
}

# Postgres Container App
resource "azurerm_container_app" "postgres_app" {
  name                         = var.postgres_app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"
  tags                         = var.tags

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

      readiness_probe {
        transport = "TCP"
        port      = var.postgres_port
      }
      liveness_probe {
        transport = "TCP"
        port      = var.postgres_port
      }
    }

    volume {
      name         = "postgres-data"
      storage_type = "AzureFile"
      storage_name = azurerm_storage_share.postgres_share.name
    }

    min_replicas = 0  # Scale to zero when idle
    max_replicas = var.postgres_max_replicas
  }

  ingress {
    external_enabled = true
    target_port      = var.postgres_port
    transport        = "tcp"
    traffic_weight {
      percentage = 100
      latest_revision = true
    }
    allow_insecure_connections = true  # Require HTTPS TODO: change to false
  }
}

# Redis Container App
resource "azurerm_container_app" "redis_app" {
  name                         = var.redis_app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"
  tags                         = var.tags

  template {
    container {
      name   = "redis"
      image  = "redis:7.2"
      cpu    = 0.25
      memory = "0.5Gi"
      command = ["redis-server", "--appendonly", "yes", "--requirepass", var.postgres_password]  # Enable AOF persistence and password protection

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
    }

    min_replicas = 0  # Scale to zero when idle
    max_replicas = var.redis_max_replicas
  }

  ingress {
    external_enabled = true
    target_port      = var.redis_port
    transport        = "tcp"
    traffic_weight {
      percentage = 100
      latest_revision = true
    }
    allow_insecure_connections = true  # Require HTTPS TODO: change to false
  }
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  name                       = "storage-diagnostics"
  target_resource_id        = azurerm_storage_account.storage.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  metric {
    category = "Transaction"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 30
    }
  }

  metric {
    category = "Capacity"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Backup Configuration for PostgreSQL
resource "azurerm_backup_policy_vm" "postgres_backup" {
  name                = "postgres-backup-policy"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }
}

# Recovery Services Vault
resource "azurerm_recovery_services_vault" "vault" {
  name                = "bank-recovery-vault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  soft_delete_enabled = true
  tags                = var.tags
}