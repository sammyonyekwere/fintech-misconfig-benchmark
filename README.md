# misconfbench-fintech

Reproducible benchmark for evaluating static and runtime cloud misconfiguration
detection in a fintech-style payment workload on Microsoft Azure.

## Current Project Status (as of 2026-07-27)

This repository is in active build-out.

- Baseline Terraform module is implemented in `modules/baseline/`.
- Core Azure resources are provisioned (resource group, VNet/subnet, storage,
	key vault, SQL server/database, service plan, Linux Function App).
- Misconfiguration toggles are defined for `mc01` to `mc10`.
- Current toggle logic implemented in code:
	- `mc01_public_storage` (storage public exposure)
	- `mc02_rbac_contributor` (overly broad role assignment)
	- `mc06_weak_tls` (weak storage TLS)
- Additional toggles are scaffolded in variables and will be implemented in
	upcoming variants.

## Repository Layout

- `modules/baseline/`: Terraform baseline deployment and misconfiguration flags.
- `variants/`: Planned variant-specific IaC overlays.
- `harness/kql/`: KQL rules for runtime detection and telemetry checks.
- `analysis/`: Analysis scripts/notebooks for detection-performance metrics.
- `results/raw/`: Raw tool outputs.
- `results/processed/`: Normalized/aggregated benchmark outputs.
- `az-cli/cli.ps1`: Azure CLI helpers used in execution workflow.

## Baseline Infrastructure (Terraform)

Implemented files:

- `modules/baseline/main.tf`
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

## Citation

Citation metadata is provided in `CITATION.cff` for GitHub and Zenodo-based
archiving/referencing.
