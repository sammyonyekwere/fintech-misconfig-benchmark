data "azurerm_subscription" "current" {}

locals {
  # SECURE: narrow role, resource-group scope
  tight_scope = azurerm_resource_group.rg.id
  tight_role  = "Storage Blob Data Reader"

  # INSECURE: Contributor access the whole subscription
  wide_scope = data.azurerm_subscription.current.id
  wide_role  = "Contributor"
}

resource "azurerm_role_assignment" "func_identity" {
  scope        = var.mc02_rbac_contributor ? local.wide_scope : local.tight_scope
  principal_id = azurerm_linux_function_app.functionapp.identity[0].principal_id

  role_definition_name = (
    var.mc02_rbac_contributor ? local.wide_role : local.tight_role
  )
}