# Combines results/static_scan_run_log.csv (KICS/Checkov/Trivy — static,
# pre-deployment) and results/policy_scan_log.csv (Azure Policy — deployed-
# state, post-deployment) into one normalised view.
#
# The two logs do NOT share a schema on purpose: the static log has a single
# n_findings column, while the policy log splits n_findings_raw (all MCSB
# non-compliant policies, mostly noise) from n_findings_mapped (only the
# mc0X-relevant ones — see the $PolicyRuleMap note in
# deployed_state_policy_scan.ps1). Reading either file with an assumption
# borrowed from the other's column names is what used to crash. This script
# normalises both into a common shape instead of forcing one schema onto the
# other.
#
# Usage: pwsh harness/show_results.ps1 [-Export results/combined_results.csv]

param(
    [string]$Export
)

function Read-StaticLog {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Warning "$Path not found — skipping static (pre-deployment) results."
        return @()
    }
    Import-Csv $Path | ForEach-Object {
        [PSCustomObject]@{
            tier          = "static"
            tool          = $_.tool
            variant       = $_.variant
            run           = $_.run
            scanned_at    = $_.scanned_at
            duration_s    = $_.duration_s
            n_findings    = $_.n_findings
            n_findings_raw = ""
            mc_detected   = $_.mc_detected
        }
    }
}

function Read-PolicyLog {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Warning "$Path not found — skipping deployed-state (Azure Policy) results."
        return @()
    }
    Import-Csv $Path | ForEach-Object {
        [PSCustomObject]@{
            tier          = "deployed-state"
            tool          = $_.tool
            variant       = $_.variant
            run           = $_.run
            scanned_at    = $_.scanned_at
            duration_s    = $_.duration_s
            # n_findings_mapped is the fair, apples-to-apples comparison against
            # the static tools' n_findings (both mean "counts toward mc0X TPR").
            # n_findings_raw is kept alongside for anyone who wants the noise figure.
            n_findings    = $_.n_findings_mapped
            n_findings_raw = $_.n_findings_raw
            mc_detected   = $_.mc_detected
        }
    }
}

$rows = @()
$rows += Read-StaticLog "results/static_scan_run_log.csv"
$rows += Read-PolicyLog "results/policy_scan_log.csv"

if ($rows.Count -eq 0) {
    Write-Error "No results found in either log — nothing to display."
    exit 1
}

$rows = $rows | Sort-Object variant, tier, tool, { [int]$_.run }

$rows | Format-Table tier, tool, variant, run, duration_s, n_findings, n_findings_raw, mc_detected -AutoSize

if ($Export) {
    $rows | Export-Csv -Path $Export -NoTypeInformation
    Write-Host "Combined results written to $Export"
}
