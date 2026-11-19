# ---------- Service Bus: pub/sub between domains ----------
resource "azurerm_servicebus_namespace" "sb" {
  name                = "sb-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  local_auth_enabled  = false
  tags                = local.tags
}

resource "azurerm_servicebus_topic" "orders" {
  name         = "orders"
  namespace_id = azurerm_servicebus_namespace.sb.id
}

resource "azurerm_servicebus_subscription" "inventory" {
  name                                 = "inventory"
  topic_id                             = azurerm_servicebus_topic.orders.id
  max_delivery_count                   = 5
  lock_duration                        = "PT1M"
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_subscription" "fulfillment" {
  name               = "fulfillment-bopis"
  topic_id           = azurerm_servicebus_topic.orders.id
  max_delivery_count = 5
}

resource "azurerm_servicebus_subscription_rule" "bopis_only" {
  name            = "bopis-only"
  subscription_id = azurerm_servicebus_subscription.fulfillment.id
  filter_type     = "SqlFilter"
  sql_filter      = "channel = 'bopis'"
}

resource "azurerm_role_assignment" "order_send" {
  scope                = azurerm_servicebus_topic.orders.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.app["order-api"].principal_id
}

resource "azurerm_role_assignment" "inv_receive" {
  scope                = azurerm_servicebus_subscription.inventory.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.app["inventory-worker"].principal_id
}

# ---------- API Management: the single front door ----------
resource "azurerm_api_management" "apim" {
  name                = "apim-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "RetailFlow"
  publisher_email     = var.alert_email
  sku_name            = "Consumption_0"
  identity {
    type = "SystemAssigned"
  }
  tags = local.tags
}

resource "azurerm_api_management_named_value" "gw" {
  name                = "gateway-secret"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "gateway-secret"
  secret              = true
  value               = random_password.gw.result
}

resource "azurerm_api_management_product" "channels" {
  product_id            = "omnichannel"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  display_name          = "Omnichannel"
  subscription_required = true
  approval_required     = false
  published             = true
}

output "gateway_url" {
  value = azurerm_api_management.apim.gateway_url
}
