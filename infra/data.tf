# Operational store for orders, inventory and products.
# ADR-0009: Cosmos DB was refused for capacity in canadacentral, canadaeast and eastus
# on the trial subscription, so dev uses Azure Table Storage (same azure-data-tables SDK
# as the Cosmos DB Table API; switching later only changes the endpoint).

resource "azurerm_storage_account" "ops" {
  name                            = "st${local.name}ops"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.rg.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [var.my_ip]
  }
  tags = local.tags
}

locals {
  table_grants = {
    order-api        = "Storage Table Data Contributor"
    inventory-worker = "Storage Table Data Contributor"
    forecast-api     = "Storage Table Data Reader"
    merch-assistant  = "Storage Table Data Reader"
  }
}

resource "azurerm_role_assignment" "tables_apps" {
  for_each             = local.table_grants
  scope                = azurerm_storage_account.ops.id
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.app[each.key].principal_id
}

resource "azurerm_role_assignment" "tables_me" {
  scope                = azurerm_storage_account.ops.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = data.azurerm_client_config.me.object_id
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  name                  = "link-privatelink-table"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "tables" {
  name                = "pe-tables"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id
  private_service_connection {
    name                           = "tables"
    private_connection_resource_id = azurerm_storage_account.ops.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "tables"
    private_dns_zone_ids = [azurerm_private_dns_zone.table.id]
  }
  tags = local.tags
}

output "tables_endpoint" {
  value = azurerm_storage_account.ops.primary_table_endpoint
}
