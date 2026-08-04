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
  #mc01
  allow_nested_items_to_be_public = var.mc01_public_storage
  public_network_access_enabled   = var.mc01_public_storage
  #mc06
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = !var.mc06_no_https

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.storage.id]
  }

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
  purge_protection_enabled = !var.mc08_no_cmk
  sku_name                    = "standard"
}

resource "random_password" "sql" {
  length  = 24
  special = true
}

resource "time_sleep" "wait_for_kv_policy" {
  depends_on      = [azurerm_key_vault_access_policy.terraform_client]
  create_duration = "30s"
}

resource "azurerm_key_vault_secret" "sql_conn" {
  name         = "sql-connection"
  value        = local.sql_conn_string
  key_vault_id = azurerm_key_vault.vault.id

  depends_on = [
    time_sleep.wait_for_kv_policy
  ]
}


# SQL
resource "azurerm_mssql_server" "sqlserver" {
  name                         = "sql${var.variant_name}server"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_server_user
  administrator_login_password = random_password.sql.result

  #SECURE: private only; INSECURE: public endpoint open
  public_network_access_enabled = var.mc03_sql_public
  minimum_tls_version           = "1.2"

  timeouts {
    create = "15m"
    delete = "15m"
  }

}

# Pattern B: firewall rule exists only in the vulnerable state
resource "azurerm_mssql_firewall_rule" "allow_internet" {
  count            = var.mc03_sql_public ? 1 : 0
  name             = "allow-all-internet"
  server_id        = azurerm_mssql_server.sqlserver.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_mssql_database" "mssqldb" {
  name         = "mssql${var.variant_name}db"
  server_id    = azurerm_mssql_server.sqlserver.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  max_size_gb  = 2
  sku_name     = "S0"
  # enclave_type = "VBS"

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

  identity {
    type = "SystemAssigned"
  }

  # mc06: false = HTTPS only (secure); true = allow plaintext HTTP
  https_only = !var.mc06_no_https

  app_settings = {
    # INSECURE: the raw credential is written into the app configuration
    "SQL_CONNECTION" = var.mc05_plaintext_secrets ? local.sql_conn_string : local.conn_secure
  }

  site_config {
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
  }
}


resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                   = "app-inbound"
    priority               = 100
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = "443"

    #SECURE: restricted CIDR; INSECURE: open to the entire internet
    source_address_prefix      = var.mc09_nsg_open_inbound ? "0.0.0.0/0" : "10.20.0.0/16"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.snet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_security_rule" "mgmt" {
  count                       = var.mc04_open_mgmt_ports ? 1 : 0
  name                        = "allow-rdp-ssh"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["22", "3389"]
  source_address_prefix       = "0.0.0.0/0"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# noisy but still-restricted NSG rule
resource "azurerm_network_security_rule" "routine" {
  count                       = var.enable_nsg_routine_update ? 1 : 0
  name                        = "app-inbound-8443"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8443"
  source_address_prefix       = "10.20.0.0/16" # still restricted and compliant
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# an automated TLS certificate renewal in Key Vault
resource "azurerm_key_vault_certificate" "app" {
  count        = var.enable_tls_cert_renewal ? 1 : 0
  name         = "cert-app-${var.variant_name}"
  key_vault_id = azurerm_key_vault.vault.id

  depends_on = [
    time_sleep.wait_for_kv_policy
  ]

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = false
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }

    x509_certificate_properties {
      subject            = "CN=payments.internal"
      validity_in_months = 12
      key_usage          = ["digitalSignature", "keyEncipherment"]
    }
  }
}


resource "azurerm_storage_account" "logs" {
  name                     = "st${var.variant_name}logs"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  https_traffic_only_enabled = !var.mc06_no_https

  # this account is never public in any variant
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.variant_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  count                      = var.mc07_logging_disabled ? 0 : 1
  name                       = "diag-kv"
  target_resource_id         = azurerm_key_vault.vault.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  enabled_log {
    category = "AuditEvent"
  }
}

resource "azurerm_monitor_diagnostic_setting" "sql" {
  count                      = var.mc07_logging_disabled ? 0 : 1
  name                       = "diag-sql"
  target_resource_id         = azurerm_mssql_database.mssqldb.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
  metric { category = "AllMetrics" }
}

resource "azurerm_key_vault_key" "cmk" {
  count           = var.mc08_no_cmk ? 0 : 1
  name            = "cmk-storage"
  key_vault_id    = azurerm_key_vault.vault.id
  key_type        = "RSA"
  key_size        = 2048
  key_opts        = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
  expiration_date = timeadd(timestamp(), "8760h")

  depends_on = [
    time_sleep.wait_for_kv_policy
  ]

  # expiration_date recomputes from timestamp() on every plan, so without
  # this it never matches state and forces a destroy+recreate on every
  # apply -- which races against Key Vault's soft-delete latency and fails
  # with "Key cmk-storage is currently being deleted". The expiration is
  # only ever meant to be set once at creation, not recalculated each run.
  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_storage_account_customer_managed_key" "data" {
  count                     = var.mc08_no_cmk ? 0 : 1
  storage_account_id        = azurerm_storage_account.data.id
  key_vault_id              = azurerm_key_vault.vault.id
  key_name                  = azurerm_key_vault_key.cmk[0].name
  user_assigned_identity_id = azurerm_user_assigned_identity.storage.id

  depends_on = [
    azurerm_key_vault_access_policy.storage_uai
  ]
}

resource "azurerm_key_vault_access_policy" "terraform_client" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create",
    "Delete",
    "Get",
    "List",
    "Purge",
    "Recover",
    "Update",
    "GetRotationPolicy",
    "SetRotationPolicy",
    "Rotate",
  ]

  secret_permissions = [
    "Get",
    "Set",
    "Delete",
    "Purge",
    "Recover",
  ]

  certificate_permissions = [
    "Create",
    "Delete",
    "Get",
    "Import",
    "List",
    "Purge",
    "Recover",
    "Update",
  ]

  storage_permissions = [
    "Get",
  ]
}

resource "azurerm_key_vault_access_policy" "functionapp" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.functionapp.identity[0].principal_id

  secret_permissions = ["Get"]
}
