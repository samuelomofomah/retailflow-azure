resource "random_string" "sfx" {
  length  = 5
  upper   = false
  special = false
}

locals {
  name = "rf${random_string.sfx.result}"
  tags = { project = "retailflow", env = "dev", owner = "samuel", costcenter = "portfolio" }
}

data "azurerm_client_config" "me" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-retailflow-dev"
  location = var.location
  tags     = local.tags
}
