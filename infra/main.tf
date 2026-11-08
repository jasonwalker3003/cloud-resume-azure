# The resource group was created by bootstrap.sh, so Terraform reads it rather than owning it.
data "azurerm_resource_group" "main" {
  name = "rg-${var.prefix}"
}

locals {
  rg       = data.azurerm_resource_group.main.name
  location = data.azurerm_resource_group.main.location
  tags     = { project = "cloud-resume", owner = "jason", env = "prod" }
}

# ---------- Website: Static Web Apps (Free plan: hosting, HTTPS, 2 custom domains) ----------
resource "azurerm_static_web_app" "site" {
  name                = "swa-${var.prefix}"
  resource_group_name = local.rg
  location            = var.swa_location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = local.tags
}

# ---------- Database: Cosmos DB for NoSQL, free tier ----------
resource "azurerm_cosmosdb_account" "db" {
  name                = "cosmos-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  free_tier_enabled   = true # first 1,000 RU/s and 25 GB free; can only be set at creation

  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = local.location
    failover_priority = 0
  }
  tags = local.tags
}

# Throughput set on the database is shared by its containers: 400 RU/s stays inside the free 1,000.
resource "azurerm_cosmosdb_sql_database" "resume" {
  name                = "resume"
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
  throughput          = 400
}

resource "azurerm_cosmosdb_sql_container" "counter" {
  name                = "counter"
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
  database_name       = azurerm_cosmosdb_sql_database.resume.name
  partition_key_paths = ["/id"]
}

resource "azurerm_cosmosdb_sql_container" "uptime" {
  name                = "uptime"
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
  database_name       = azurerm_cosmosdb_sql_database.resume.name
  partition_key_paths = ["/day"]
  default_ttl         = 7776000 # check results delete themselves after 90 days
}

# ---------- Monitoring: Log Analytics + Application Insights ----------
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5 # cost guard
  tags                = local.tags
}

resource "azurerm_application_insights" "ai" {
  name                = "appi-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  workspace_id        = azurerm_log_analytics_workspace.logs.id
  application_type    = "web"
  tags                = local.tags
}

# ---------- API: Azure Functions, Flex Consumption ----------
resource "azurerm_storage_account" "func" {
  name                            = "st${var.prefix}func"
  resource_group_name             = local.rg
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "deploy" {
  name                  = "deployments" # Flex Consumption stores your code package here
  storage_account_id    = azurerm_storage_account.func.id
  container_access_type = "private"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  os_type             = "Linux"
  sku_name            = "FC1" # Flex Consumption
  tags                = local.tags
}

resource "azurerm_function_app_flex_consumption" "api" {
  name                = "func-${var.prefix}"
  resource_group_name = local.rg
  location            = local.location
  service_plan_id     = azurerm_service_plan.func.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.func.primary_blob_endpoint}${azurerm_storage_container.deploy.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.func.primary_access_key

  runtime_name           = "python"
  runtime_version        = var.python_version
  instance_memory_in_mb  = 512
  maximum_instance_count = 40

  identity {
    type = "SystemAssigned" # the app's own identity, used to reach Cosmos DB without keys
  }

  app_settings = {
    COSMOS_ENDPOINT = azurerm_cosmosdb_account.db.endpoint
    COSMOS_DATABASE = azurerm_cosmosdb_sql_database.resume.name
    SITE_URL        = "https://${azurerm_static_web_app.site.default_host_name}"
    EXPECTED_TEXT   = var.expected_text
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.ai.connection_string
    cors {
      allowed_origins = ["https://${azurerm_static_web_app.site.default_host_name}"]
    }
  }
  tags = local.tags

  lifecycle {
    # Azure adds this tag to link the app to Application Insights in the portal.
    ignore_changes = [tags["hidden-link: /app-insights-resource-id"]]
  }
}

# Let the function's identity read and write Cosmos data (built-in Data Contributor role).
resource "azurerm_cosmosdb_sql_role_assignment" "func" {
  resource_group_name = local.rg
  account_name        = azurerm_cosmosdb_account.db.name
  role_definition_id  = "${azurerm_cosmosdb_account.db.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_function_app_flex_consumption.api.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.db.id
}

# ---------- Alerting: email when a function throws an error (a failed uptime check) ----------
resource "azurerm_monitor_action_group" "email" {
  name                = "ag-${var.prefix}"
  resource_group_name = local.rg
  short_name          = "resumeops"
  email_receiver {
    name                    = "owner"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "site_down" {
  name                = "alert-${var.prefix}-site-down"
  resource_group_name = local.rg
  scopes              = [azurerm_application_insights.ai.id]
  description         = "An uptime check failed or the API threw an error"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "exceptions/count"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
  }
  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
  tags = local.tags
}
