$variants = "hardened","vuln-01-public-storage","vuln-02-rbac-contributor","vuln-03-sql-public","vuln-04-open-mgmt-ports","vuln-05-plaintext-secrets","vuln-06-no-https","vuln-07-logging-disabled","vuln-08-no-cmk","vuln-09-nsg-open-inbound","vuln-10-sp-nonexpiring-owner"

# every mc0X flag modules/baseline/variables.tf declares
$mcFlags = "mc01_public_storage","mc02_rbac_contributor","mc03_sql_public","mc04_open_mgmt_ports","mc05_plaintext_secrets","mc06_no_https","mc07_logging_disabled","mc08_no_cmk","mc09_nsg_open_inbound","mc10_sp_nonexpiring"

# which flag each variant isolates ("hardened" has none -> all stay false)
$variantFlag = @{
    "vuln-01-public-storage"       = "mc01_public_storage"
    "vuln-02-rbac-contributor"     = "mc02_rbac_contributor"
    "vuln-03-sql-public"           = "mc03_sql_public"
    "vuln-04-open-mgmt-ports"      = "mc04_open_mgmt_ports"
    "vuln-05-plaintext-secrets"    = "mc05_plaintext_secrets"
    "vuln-06-no-https"             = "mc06_no_https"
    "vuln-07-logging-disabled"     = "mc07_logging_disabled"
    "vuln-08-no-cmk"               = "mc08_no_cmk"
    "vuln-09-nsg-open-inbound"     = "mc09_nsg_open_inbound"
    "vuln-10-sp-nonexpiring-owner" = "mc10_sp_nonexpiring"
}

$baselineTfvars = "modules/baseline/terraform.tfvars"

New-Item -ItemType Directory -Force scan_raw | Out-Null
foreach ($v in $variants) {
    $d = "variants/$v"

    # flip just this variant's mc0X flag to true in the baseline tfvars, rest false,
    # so kics can scan modules/baseline directly without crossing a module boundary
    $activeFlag = $variantFlag[$v]
    $content = Get-Content $baselineTfvars
    foreach ($flag in $mcFlags) {
        $value = if ($flag -eq $activeFlag) { "true" } else { "false" }
        $content = $content -replace "^\s*$flag\s*=.*", "$flag = $value"
    }
    Set-Content $baselineTfvars $content

    kics scan -p modules/baseline -o scan_raw --output-name "kics_$v" --report-formats json
    checkov -d $d --framework terraform -o json > "scan_raw/checkov_$v.json"
    trivy config $d -f json > "scan_raw/trivy_$v.json"
}