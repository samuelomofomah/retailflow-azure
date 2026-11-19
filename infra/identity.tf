resource "azurerm_user_assigned_identity" "app" {
  for_each            = toset(["order-api", "inventory-worker", "forecast-api", "merch-assistant"])
  name                = "id-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}
