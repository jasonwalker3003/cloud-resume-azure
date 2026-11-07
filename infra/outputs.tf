output "site_url" {
  value = "https://${azurerm_static_web_app.site.default_host_name}"
}
output "api_base_url" {
  value = "https://${azurerm_function_app_flex_consumption.api.default_hostname}/api"
}
output "function_app_name" {
  value = azurerm_function_app_flex_consumption.api.name
}
output "static_web_app_name" {
  value = azurerm_static_web_app.site.name
}
output "resource_group_name" {
  value = local.rg
}
