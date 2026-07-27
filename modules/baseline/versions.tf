# Provider Sources
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6"
    }
  }
}

data "azurerm_client_config" "current" {}

# Configure Azure Provider
provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
  features {}
}