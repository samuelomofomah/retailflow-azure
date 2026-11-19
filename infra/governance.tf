data "azurerm_policy_definition" "locations" {
  display_name = "Allowed locations"
}

data "azurerm_policy_definition" "kv_protect" {
  display_name = "Key vaults should have deletion protection enabled"
}

resource "azurerm_resource_group_policy_assignment" "locations" {
  name                 = "allowed-locations"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.locations.id
  parameters = jsonencode({
    listOfAllowedLocations = { value = ["canadacentral", "canadaeast", "eastus"] }
  })
}

resource "azurerm_resource_group_policy_assignment" "kv" {
  name                 = "kv-deletion-protection"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.kv_protect.id
}

resource "azurerm_consumption_budget_resource_group" "b" {
  name              = "budget-retailflow"
  resource_group_id = azurerm_resource_group.rg.id
  amount            = 75
  time_grain        = "Monthly"
  time_period {
    start_date = "2026-11-01T00:00:00Z"
  }
  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }
  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }
}
