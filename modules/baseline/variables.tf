variable "subscription_id" {
  type = string
}

variable "variant_name" {
  type = string
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "sql_server_user" {
  type = string
}


variable "os_type" {
  type    = string
  default = "Linux"
}

# -- Table 1 misconfiguration switches (false = secure)
variable "mc01_public_storage" {
  type    = bool
  default = false
}

variable "mc02_rbac_contributor" {
  type    = bool
  default = false
}

variable "mc03_sql_public" {
  type    = bool
  default = false
}

variable "mc04_open_mgmt_ports" {
  type    = bool
  default = false
}

variable "mc05_plaintext_secrets" {
  type    = bool
  default = false
}

variable "mc06_no_https" {
  type    = bool
  default = false
}

variable "mc07_logging_disabled" {
  type    = bool
  default = false
}

variable "mc08_no_cmk" {
  type    = bool
  default = false
}

variable "mc09_nsg_open_inbound" {
  type    = bool
  default = false
}

variable "mc10_sp_nonexpiring" {
  type    = bool
  default = false
}

variable "enable_credential_rotation" {
  type    = bool
  default = false
}


