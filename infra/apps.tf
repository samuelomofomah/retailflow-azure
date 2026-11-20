resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${local.name}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id   = azurerm_subnet.aca.id
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
  tags = local.tags
  lifecycle {
    ignore_changes = [infrastructure_resource_group_name]
  }
}

resource "azurerm_role_assignment" "order_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app["order-api"].principal_id
}

# KEDA needs to read the message count on the inventory subscription
resource "azurerm_role_assignment" "inv_scaler" {
  scope                = azurerm_servicebus_subscription.inventory.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_user_assigned_identity.app["inventory-worker"].principal_id
}

locals {
  common_env = {
    TABLES_ENDPOINT                       = azurerm_storage_account.ops.primary_table_endpoint
    SB_FQDN                               = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.appi.connection_string
  }
}

resource "azurerm_container_app" "order" {
  name                         = "ca-order-api"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app["order-api"].id]
  }
  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app["order-api"].id
  }
  secret {
    name                = "gateway-secret"
    identity            = azurerm_user_assigned_identity.app["order-api"].id
    key_vault_secret_id = azurerm_key_vault_secret.gw.versionless_id
  }
  ingress {
    external_enabled = true
    target_port      = 8000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  template {
    min_replicas = 1
    max_replicas = 5
    container {
      name   = "order-api"
      image  = "${azurerm_container_registry.acr.login_server}/order-api:v1"
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app["order-api"].client_id
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "order-api"
      }
      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.key
          value = env.value
        }
      }
      env {
        name        = "GATEWAY_SECRET"
        secret_name = "gateway-secret"
      }
      liveness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/healthz"
      }
    }
    http_scale_rule {
      name                = "http"
      concurrent_requests = "50"
    }
  }
  tags = local.tags
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
  depends_on = [azurerm_role_assignment.acrpull, azurerm_role_assignment.order_kv]
}

resource "azurerm_container_app" "inventory" {
  name                         = "ca-inventory-worker"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app["inventory-worker"].id]
  }
  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app["inventory-worker"].id
  }
  template {
    min_replicas = 0
    max_replicas = 5
    container {
      name   = "inventory-worker"
      image  = "${azurerm_container_registry.acr.login_server}/inventory-worker:v1"
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app["inventory-worker"].client_id
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "inventory-worker"
      }
      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
  tags = local.tags
  lifecycle {
    ignore_changes = [template[0].container[0].image, template[0].custom_scale_rule]
  }
  depends_on = [azurerm_role_assignment.acrpull]
}

# ---------- Publish the order API through API Management ----------
resource "azurerm_api_management_api" "retail" {
  name                  = "retail-api"
  resource_group_name   = azurerm_resource_group.rg.name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Retail API"
  path                  = "retail"
  protocols             = ["https"]
  service_url           = "https://${azurerm_container_app.order.ingress[0].fqdn}"
  subscription_required = true
}

resource "azurerm_api_management_api_operation" "place" {
  operation_id        = "place-order"
  api_name            = azurerm_api_management_api.retail.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Place order"
  method              = "POST"
  url_template        = "/orders"
}

resource "azurerm_api_management_api_operation" "get" {
  operation_id        = "get-order"
  api_name            = azurerm_api_management_api.retail.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Get order"
  method              = "GET"
  url_template        = "/orders/{orderId}"
  template_parameter {
    name     = "orderId"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_policy" "retail" {
  api_name            = azurerm_api_management_api.retail.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/apim-policy.xml")
  depends_on          = [azurerm_api_management_named_value.gw]
}

resource "azurerm_api_management_product_api" "retail" {
  product_id          = azurerm_api_management_product.channels.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  api_name            = azurerm_api_management_api.retail.name
}

resource "azurerm_api_management_subscription" "web" {
  display_name        = "web-channel"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  product_id          = azurerm_api_management_product.channels.id
  state               = "active"
}

output "order_api_fqdn" {
  value = azurerm_container_app.order.ingress[0].fqdn
}

output "web_key" {
  value     = azurerm_api_management_subscription.web.primary_key
  sensitive = true
}
