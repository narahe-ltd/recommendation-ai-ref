variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "bankrg"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "EastUS"
}

variable "container_app_env_name" {
  description = "Name of the Container App Environment"
  type        = string
  default     = "bank-ca-env"
}

variable "postgres_app_name" {
  description = "Name of the Postgres Container App"
  type        = string
  default     = "bank-postgres-app"
}

variable "redis_app_name" {
  description = "Name of the Redis Container App"
  type        = string
  default     = "bank-redis-app"
}

variable "postgres_password" {
  description = "Password for PostgreSQL user"
  type        = string
  sensitive   = true
  default     = "test@123$"
  validation {
    condition     = length(var.postgres_password) >= 12
    error_message = "PostgreSQL password must be at least 12 characters long."
  }
}

variable "redis_port" {
  description = "Port for Redis"
  type        = number
  default     = 6379
}

variable "postgres_port" {
  description = "Port for PostgreSQL"
  type        = number
  default     = 5432
}

variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "postgres_storage_quota" {
  description = "Storage quota in GB for PostgreSQL data"
  type        = number
  default     = 10
  validation {
    condition     = var.postgres_storage_quota >= 5
    error_message = "PostgreSQL storage quota must be at least 5GB."
  }
}

variable "redis_storage_quota" {
  description = "Storage quota in GB for Redis data"
  type        = number
  default     = 5
  validation {
    condition     = var.redis_storage_quota >= 1
    error_message = "Redis storage quota must be at least 1GB."
  }
}

variable "postgres_max_replicas" {
  description = "Maximum number of PostgreSQL replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.postgres_max_replicas >= 1 && var.postgres_max_replicas <= 10
    error_message = "PostgreSQL max replicas must be between 1 and 10."
  }
}

variable "redis_max_replicas" {
  description = "Maximum number of Redis replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.redis_max_replicas >= 1 && var.redis_max_replicas <= 10
    error_message = "Redis max replicas must be between 1 and 10."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either dev or prod."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "bank-recommendation"
    ManagedBy   = "terraform"
  }
}

variable "auto_teardown_enabled" {
  description = "Whether to enable auto-teardown for cost savings during non-business hours"
  type        = bool
  default     = false
}