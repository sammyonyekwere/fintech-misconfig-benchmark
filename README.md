# misconfbench-fintech

Reproducible benchmark for evaluating static and runtime cloud misconfiguration detection in a fintech-style payment workload on Microsoft Azure.

## Project Status

This repository is an active misconfiguration benchmark. The baseline Terraform module is implemented and captures a broad set of Azure security and configuration cases for controlled testing.

Implemented in `modules/baseline/`:

- Resource group, VNet, subnet, storage accounts, Key Vault, SQL server and
	database, service plan, Linux Function App, and NSG controls.
- Identity and access wiring for the Function App, a sample Azure AD application/service principal, and a user-assigned identity for storage CMK workflows.
- Key Vault access policies for the deploying identity, the storage
	user-assigned identity, and the Function App's system-assigned identity
	(required for the app to resolve its Key Vault secret reference at
	runtime).
- Shared helpers in `locals.tf` for scope selection and SQL connection-string
	construction.
- Misconfiguration toggles from `mc01` to `mc10`, wired into the baseline resources where applicable.

Current toggle behavior in code:

- `mc01_public_storage` enables public storage exposure.
- `mc02_rbac_contributor` switches the Function App identity from a narrow
	resource-group role to subscription-wide Contributor.
- `mc03_sql_public` opens SQL to public network access and adds an allow-all
	firewall rule.
- `mc04_open_mgmt_ports` opens common management ports in the NSG.
- `mc05_plaintext_secrets` writes the SQL connection string directly into app
	settings instead of using a Key Vault reference.
- `mc06_no_https` disables HTTPS-only enforcement on the storage accounts and
	the Function App, allowing plaintext HTTP traffic. TLS version itself is
	pinned to 1.2 on storage, SQL, and the Function App, since Azure now
	enforces a TLS 1.2 floor platform-wide and no longer allows provisioning
	weaker versions.
- `mc07_logging_disabled` disables diagnostic settings for Key Vault and SQL.
- `mc08_no_cmk` disables the customer-managed key path for storage.
- `mc09_nsg_open_inbound` broadens inbound NSG exposure.
- `mc10_sp_nonexpiring` makes the service principal access path overly broad and
	long-lived.
- `enable_credential_rotation` supports rotating the generated application
	password during testing.

## Repository Layout

- `modules/baseline/`: Terraform baseline deployment, locals, identity, and
	misconfiguration flags.
- `variants/`: Planned variant-specific IaC overlays.
- `harness/kql/`: KQL rules for runtime detection and telemetry checks.
- `analysis/`: Analysis scripts/notebooks for detection-performance metrics.
- `results/raw/`: Raw tool outputs.
- `results/processed/`: Normalized/aggregated benchmark outputs.
- `az-cli/cli.ps1`: Azure CLI helpers used in execution workflow.

## Baseline Infrastructure

Implemented files:

- `modules/baseline/main.tf`
- `modules/baseline/locals.tf`
- `modules/baseline/identity.tf`
- `modules/baseline/variables.tf`
- `modules/baseline/versions.tf`

Provider stack:

- `hashicorp/azurerm` `~>4.1`
- `hashicorp/azuread` `~>3.0`
- `hashicorp/random` `~>3.6`
- `hashicorp/time` `~>0.11`

## Validation Status

The baseline has been applied successfully end-to-end with Terraform for both
the hardened and vulnerable variants, including the Key Vault policy and CMK
timing adjustments needed for the deploy identity, and the Key Vault access
policy needed for the Function App to resolve its Key Vault secret reference.

Two platform-level constraints were found and adjusted for during validation:

- Azure SQL logical servers now enforce a TLS 1.2 floor and reject creation
	requests specifying a lower `minimum_tls_version`. TLS version is pinned to
	1.2 across SQL, storage, and the Function App; `mc06` now toggles
	HTTPS-only enforcement instead of TLS version (see `mc06_no_https` above).
- `azurerm_mssql_database` does not support `enclave_type = "VBS"` on the
	DTU-based `S0` SKU used in this baseline; the enclave setting has been
	removed.

### Operational note: redeploying a variant

The Key Vault (`purge_protection_enabled = true` whenever `mc08_no_cmk =
false`, the default) cannot be purged once destroyed — it only soft-deletes,
and Azure requires the same vault name to stay reserved for
`soft_delete_retention_days` (7 days). Tearing an environment down with
`terraform destroy` (rather than deleting the resource group directly through
Azure) keeps Terraform state in sync with this behavior. If a resource group
is deleted out-of-band, the next `apply` for the same `variant_name` will
auto-recover the soft-deleted vault along with its child objects (keys,
secrets, access policies, diagnostic settings), which then need to be
`terraform import`-ed back into state before `apply` can proceed.

## Misconfiguration Switches

All switches default to secure (`false`) and are controlled through
`terraform.tfvars`.

- `mc01_public_storage`
- `mc02_rbac_contributor`
- `mc03_sql_public`
- `mc04_open_mgmt_ports`
- `mc05_plaintext_secrets`
- `mc06_no_https`
- `mc07_logging_disabled`
- `mc08_no_cmk`
- `mc09_nsg_open_inbound`
- `mc10_sp_nonexpiring`

The secure path keeps the function app credential out of plain app settings by
using a Key Vault reference when plaintext secrets are disabled.

## Quick Start

1. Authenticate to Azure:

```powershell
az login
az account set --subscription <subscription-id>
```

2. Go to baseline module:

```powershell
cd modules/baseline
```

3. Initialize Terraform:

```powershell
terraform init
```

4. Review plan:

```powershell
terraform plan -var-file="terraform.tfvars"
```

The current baseline plan covers identity binding, NSG association, SQL public-access variants, Key Vault secret storage, CMK wiring, and the Function App connection-string handling.

5. Apply:

```powershell
terraform apply -var-file="terraform.tfvars"
```

6. Destroy when finished:

```powershell
terraform destroy -var-file="terraform.tfvars" -auto-approve
```

## Security Note

Do not keep real credentials in committed tfvars files. Use environment
variables, secret stores, or untracked local tfvars overrides for sensitive
values.

The repository currently contains sample configuration values in
`modules/baseline/terraform.tfvars`; treat them as local test inputs rather
than production secrets.

## Citation

Citation metadata is provided in `CITATION.cff` for GitHub and Zenodo-based
archiving and referencing.
