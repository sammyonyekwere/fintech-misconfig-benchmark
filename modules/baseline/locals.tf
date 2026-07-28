locals {
  # SECURE: narrow role, resource-group scope
  tight_scope = azurerm_resource_group.rg.id
  tight_role  = "Storage Blob Data Reader"

  # INSECURE: Contributor access the whole subscription
  wide_scope = data.azurerm_subscription.current.id
  wide_role  = "Contributor"

  sql_conn_string = format(
    "Server=tcp:%s,1433;Database=paymentsdb;User ID=sqladminuser;Password=%s;Encrypt=true;",
    azurerm_mssql_server.sqlserver.fully_qualified_domain_name,
    random_password.sql.result,
  )

  # SECURE: the app only ever sees a Key Vault reference
  conn_secure = format(
    "@Microsoft.KeyVault(SecretUri=%s)",
    azurerm_key_vault_secret.sql_conn.versionless_id,
  )
}