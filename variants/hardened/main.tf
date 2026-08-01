terraform {
  required_version = ">= 1.9.0"
  backend "azurerm" {}
}

module "baseline" {
  source = "../../modules/baseline"

  subscription_id = var.subscription_id
  variant_name    = var.variant_name
  sql_server_user = var.sql_server_user

  mc01_public_storage    = var.mc01_public_storage
  mc02_rbac_contributor  = var.mc02_rbac_contributor
  mc03_sql_public        = var.mc03_sql_public
  mc04_open_mgmt_ports   = var.mc04_open_mgmt_ports
  mc05_plaintext_secrets = var.mc05_plaintext_secrets
  mc06_no_https          = var.mc06_no_https
  mc07_logging_disabled  = var.mc07_logging_disabled
  mc08_no_cmk            = var.mc08_no_cmk
  mc09_nsg_open_inbound  = var.mc09_nsg_open_inbound
  mc10_sp_nonexpiring    = var.mc10_sp_nonexpiring

  enable_credential_rotation = var.enable_credential_rotation
  enable_nsg_routine_update  = var.enable_nsg_routine_update
  enable_tls_cert_renewal    = var.enable_tls_cert_renewal
  

}