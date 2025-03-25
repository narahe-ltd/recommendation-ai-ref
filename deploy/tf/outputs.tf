output "postgres_app_url" {
  description = "The fully qualified domain name of the Postgres Container App"
  value       = azurerm_container_app.postgres_app.latest_revision_fqdn
}

output "redis_app_url" {
  description = "The fully qualified domain name of the Redis Container App"
  value       = azurerm_container_app.redis_app.latest_revision_fqdn
}

output "postgres_connection_string" {
  description = "Connection string for PostgreSQL"
  value       = "psql -h ${azurerm_container_app.postgres_app.latest_revision_fqdn} -p ${var.postgres_port} -U bank_user -d bank_recommendations"
}

output "redis_connection_string" {
  description = "Connection string for Redis"
  value       = "redis-cli -h ${azurerm_container_app.redis_app.latest_revision_fqdn} -p ${var.redis_port}"
}