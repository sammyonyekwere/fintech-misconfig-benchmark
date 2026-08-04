# Usage: pwsh harness/policy_whatif_scan.ps1 <variant> <run>

param(
    [Parameter(Mandatory, Position=0)]
    [string]$Variant,

    [Parameter(Mandatory, Position=1)]
    [int]$Run
)

$logPath = "results/policy_whatif_log.csv"
if (-not (Test-Path $logPath)) {
    "tool,variant,run,scanned_at,duration_s,blocked,denied_by" | Set-Content $logPath
}

$scannedAt = (Get-Date).ToUniversalTime().ToString("o")

Write-Host "=== Attempting apply for $Variant (what-if via deny policy) ==="
# Pass $Run through explicitly -- run_variant.sh defaults to run 1 when the
# second argument is omitted, which would make repeated invocations (or
# deployed_state_policy_scan.ps1 targeting the same variant) silently
# overwrite each other's results/logs/<variant>_run<N>.log via `tee`.
#
# Timed manually rather than via Measure-Command { ... }, since
# Measure-Command swallows the scriptblock's console output instead of
# streaming it live -- that's what made the earlier stuck run look like it
# was producing zero output for 10+ minutes, when it may just have been
# running normally with its progress hidden from view.
$start = Get-Date
bash ./scripts/run_variant.sh $Variant $Run
$dur = (Get-Date) - $start
$applyFailed = ($LASTEXITCODE -ne 0)

# run_variant.sh writes here itself via `tee` -- no prefix.
$applyLogPath = "results/logs/${Variant}_run${Run}.log"
$output = if (Test-Path $applyLogPath) { Get-Content $applyLogPath -Raw } else { "" }

$blocked = [bool]($output -match "RequestDisallowedByPolicy")
$deniedBy = ""
# The denial's "Policy identifiers" payload is JSON, e.g.:
#   "policyDefinition":{"name":"mc01-deny-public-storage","id":"...","version":"1.0.0"}
# -- confirmed against a real denial, not assumed.
if ($blocked -and ($output -match '"policyDefinition":\s*\{\s*"name"\s*:\s*"([^"]+)"')) {
    $deniedBy = $matches[1]
}

if ($applyFailed -and -not $blocked) {
    Write-Warning "terraform apply failed for $Variant but not with a recognised policy denial -- check $applyLogPath for the real cause before trusting this row (e.g. an expired auth token, not a deny policy)."
}

$newRow = [PSCustomObject]@{
    tool       = "azpolicy-whatif"
    variant    = $Variant
    run        = $Run
    scanned_at = $scannedAt
    duration_s = $dur.TotalSeconds
    blocked    = $blocked
    denied_by  = $deniedBy
}

# Replace any existing row for this variant+run rather than erroring or
# appending a duplicate -- lets you re-run the same variant/run repeatedly
# while debugging without hand-editing the CSV each time.
$rows = @(Import-Csv $logPath | Where-Object { -not ($_.variant -eq $Variant -and $_.run -eq "$Run") })
$rows += $newRow
$rows | Export-Csv -Path $logPath -NoTypeInformation

Write-Host "Done. Duration: $($dur.TotalSeconds)s | blocked: $blocked | denied by: $deniedBy"
if ($blocked) {
    Write-Host "Partial deployment likely -- other resources in this apply may have been created before the denial."
}
Write-Host "Remember to run './scripts/teardown.sh $Variant' to clean up, whether blocked or not."
