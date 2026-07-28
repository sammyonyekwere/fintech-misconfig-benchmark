data "azurerm_subscription" "current" {}



resource "azurerm_role_assignment" "func_identity" {
  scope        = var.mc02_rbac_contributor ? local.wide_scope : local.tight_scope
  principal_id = azurerm_linux_function_app.functionapp.identity[0].principal_id

  role_definition_name = (
    var.mc02_rbac_contributor ? local.wide_role : local.tight_role
  )
}

resource "azuread_application" "payments" {
  display_name = "sp-${var.variant_name}-payments"
}

resource "azuread_service_principal" "payments" {
  client_id = azuread_application.payments.client_id
}

resource "azuread_application_password" "payments" {
  application_id = azuread_application.payments.id

  #SECURE: 90-day credential; INSECURE: effectively never expires
  end_date = var.mc10_sp_nonexpiring ? "2999-12-31T00:00:00Z" : timeadd(timestamp(), "2160h")

  rotate_when_changed = var.enable_credential_rotation ? {
    rotation = timestamp()
  } : {}
}

resource "azurerm_role_assignment" "sp_payments" {
  #SECURE: Reader on the resource group; INSECURE: Owner on the subscription
  scope = (
    var.mc10_sp_nonexpiring ? local.wide_scope : local.tight_scope
  )

  role_definition_name = var.mc10_sp_nonexpiring ? "Owner" : "Reader"
  principal_id         = azuread_service_principal.payments.object_id
}

resource "azurerm_user_assigned_identity" "storage" {
  name                = "uai-${var.variant_name}-storage"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_key_vault_access_policy" "storage_uai" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.storage.principal_id

  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey",
  ]
}
