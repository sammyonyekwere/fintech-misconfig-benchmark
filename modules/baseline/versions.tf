# Provider Sources
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

# Configure Azure Provider
provider "azurerm" {
  resource_provider_registrations = "none"
  futures {}
}