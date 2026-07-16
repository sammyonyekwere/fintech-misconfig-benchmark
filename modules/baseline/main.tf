# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.variant_name}"
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-payments"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.20.0.0/16"]
}

# Subnet
resource "azurerm_subnet" "snet" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Storage
resource "azurerm_storage_account" "data" {
  name                     = "st${var.variant_name}data"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # SECURE default = false;insecure when flag is true
  ## allow_nested_items_to_be_public = var.mc01_public_storage
  ## public_network_access_enabled = var.mc01_public_storage
  ## min_tls_version = var.mc06_weak_tls ? "TLS1_0" : "TLS1_2"

  tags = {
    environment = "dev"
  }
}


# Key Vault
resource "azurerm_key_vault" "vault" {
  name                        = "vault${var.variant_name}"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  enable_rbac_authorization   = false
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}


# SQL
resource "azurerm_mssql_server" "sqlserver" {
  name                         = "sql${var.variant_name}server"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_server_user
  administrator_login_password = var.sql_server_password

}

resource "azurerm_mssql_database" "mssqldb" {
  name         = "mssql${var.variant_name}db"
  server_id    = azurerm_mssql_server.sqlserver.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  max_size_gb  = 2
  sku_name     = "S0"
  enclave_type = "VBS"

  tags = {
    environment = "staging"
  }

  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = false
  }
}


# App Service
resource "azurerm_service_plan" "serviceplan" {
  name                = "app${var.variant_name}service"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1"
}



# Function App
resource "azurerm_linux_function_app" "functionapp" {
  name                = "function${var.variant_name}app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.data.name
  storage_account_access_key = azurerm_storage_account.data.primary_access_key
  service_plan_id            = azurerm_service_plan.serviceplan.id

  site_config {}
}