variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "bank-rg"
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
  default     = "secure_password_123"
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