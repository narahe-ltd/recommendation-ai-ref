# backend/main.tf


# Variables (optional, to make it reusable)
variable "location" {
  description = "Azure region for backend resources"
  default     = "eastus"  # Adjust as needed
}

variable "tags" {
  description = "Tags for resources"
  type        = map(string)
  default     = {
    environment = "terraform-backend"
  }
}

# Random string to ensure storage account name uniqueness
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Backend Resource Group
resource "azurerm_resource_group" "backend_rg" {
  name     = "terraform-backend-rg"
  location = var.location
  tags     = var.tags
}

# Backend Storage Account
resource "azurerm_storage_account" "backend_storage" {
  name                     = "tfbackend${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.backend_rg.name
  location                 = azurerm_resource_group.backend_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

# Backend Storage Container
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.backend_storage.name
  container_access_type = "private"
}

# Outputs to use in the main project
output "backend_resource_group_name" {
  value = azurerm_resource_group.backend_rg.name
}

output "backend_storage_account_name" {
  value = azurerm_storage_account.backend_storage.name
}

output "backend_container_name" {
  value = azurerm_storage_container.tfstate.name
}