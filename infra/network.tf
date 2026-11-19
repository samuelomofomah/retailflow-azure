resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.name}"
  address_space       = ["10.20.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.0.0/23"]
  delegation {
    name = "aca"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.2.0/24"]
}

resource "azurerm_private_dns_zone" "z" {
  for_each            = toset(["privatelink.vaultcore.azure.net", "privatelink.documents.azure.com"])
  name                = each.key
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "l" {
  for_each              = azurerm_private_dns_zone.z
  name                  = "link-${replace(each.key, ".", "-")}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}
