output "postgres_app_name" {
  value = azurerm_container_app.postgres.name
}

output "redis_app_name" {
  value = azurerm_container_app.redis.name
}