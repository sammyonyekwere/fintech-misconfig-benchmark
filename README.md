# misconfbench-fintech

Reproducible benchmark for evaluating static and runtime cloud misconfiguration
detection in a fintech-style payment workload on Microsoft Azure.

## Current Project Status

This repository is in active build-out and the baseline Terraform module is now
capturing a broader set of fintech Azure misconfiguration cases.

Implemented in `modules/baseline/`:

- Resource group, VNet, subnet, storage accounts, Key Vault, SQL server and
	database, service plan, Linux Function App, and NSG controls.
- Identity and access wiring for the Function App and a sample Azure AD service
	principal.
- Shared helpers in `locals.tf` for scope selection and SQL connection-string
	construction.
- Misconfiguration toggles from `mc01` to `mc10`, with several already wired
	into the baseline resources.

Current toggle behavior in code:

- `mc01_public_storage` enables public storage exposure.
- `mc02_rbac_contributor` switches the Function App identity from a narrow
	resource-group role to subscription-wide Contributor.
- `mc03_sql_public` opens SQL to public network access and adds an allow-all
	firewall rule.
- `mc04_open_mgmt_ports` opens common management ports in the NSG.
- `mc05_plaintext_secrets` writes the SQL connection string directly into app
	settings instead of using a Key Vault reference.
- `mc06_weak_tls` weakens TLS settings for storage, SQL, and the Function App.
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

## Baseline Infrastructure (Terraform)

Implemented files:

- `modules/baseline/main.tf`
- `modules/baseline/locals.tf`
- `modules/baseline/identity.tf`
- `modules/baseline/variables.tf`
- `modules/baseline/versions.tf`

Provider stack:

- `hashicorp/azurerm` `=4.1.0`
- `hashicorp/azuread` `~>3.0`
- `hashicorp/random` `~>3.6`

## Misconfiguration Switches

All switches default to secure (`false`) and are controlled through
`terraform.tfvars`.

- `mc01_public_storage`
- `mc02_rbac_contributor`
- `mc03_sql_public`
- `mc04_open_mgmt_ports`
- `mc05_plaintext_secrets`
- `mc06_weak_tls`
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

The current baseline plan now covers identity binding, NSG association, SQL
public-access variants, Key Vault secret storage, and the Function App's
connection-string handling.

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
archiving/referencing.
