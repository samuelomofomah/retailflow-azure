resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.name}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.me.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = [var.my_ip]
  }
  tags = local.tags
}

resource "azurerm_role_assignment" "me_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.me.object_id
}

resource "random_password" "gw" {
  length  = 40
  special = false
}

resource "azurerm_key_vault_secret" "gw" {
  name         = "gateway-secret"
  value        = random_password.gw.result
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_role_assignment.me_kv]
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id
  private_service_connection {
    name                           = "kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.z["privatelink.vaultcore.azure.net"].id]
  }
  tags = local.tags
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_role_assignment" "acrpull" {
  for_each             = azurerm_user_assigned_identity.app
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = each.value.principal_id
}
