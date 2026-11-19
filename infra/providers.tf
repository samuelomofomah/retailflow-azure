terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.10" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "azurerm" {
    resource_group_name  = "rg-retailflow-tfstate"
    storage_account_name = "strftfstate24485"
    container_name       = "tfstate"
    key                  = "retailflow-dev.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
