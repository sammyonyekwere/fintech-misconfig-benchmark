# Deployed-state compliance scan (Azure Policy) — NOT static IaC analysis.
#
# This evaluates a resource's actual, already-deployed configuration in Azure
# (via a forced policy compliance re-scan), which is a different detection
# tier from harness/run_static.py (KICS/Checkov/Trivy, which scan Terraform
# *source* and never touch Azure) and from harness/kql/ (continuous,
# event/telemetry-based runtime detection). See docs/01-implementation.md
# for the three-tier breakdown: static (pre-deployment) / deployed-state
# (post-deployment, this script) / runtime (continuous, event-driven).
#
# Usage: pwsh harness/deployed_state_policy_scan.ps1 <variant> <run>

param(
    [Parameter(Mandatory, Position=0)]
    [string]$Variant,

    [Parameter(Mandatory, Position=1)]
    [int]$Run
)

# --- mc0X -> Azure Policy mapping -------------------------------------------------
# Same empirical method as results/rule_map.json: run this script against `hardened`
# and against each single-fault `vuln-0X`, diff which policyDefinitionReferenceId
# values go NonCompliant that weren't already NonCompliant on hardened, and add
# those entries here. Until populated, n_findings_mapped will (correctly) read 0 --
# MCSB's ~20+ raw non-compliant policies are mostly baseline-design objections
# (private-link, shared-key, DDoS, SQL auditing), not your injected faults, and
# should not count toward TPR until verified against this map.
$PolicyRuleMap = @{
    # "<policyDefinitionReferenceId>" = "mc01_public_storage"
}

function Get-PolicyStates {
    param([string]$ResourceGroup)

    $rawText = az policy state list --resource-group $ResourceGroup -o json
    $parsed = $rawText | ConvertFrom-Json

    # Observed to return either a flat array or a { value: [...] } wrapper
    # depending on CLI/API version -- handle both explicitly. Critically,
    # only attempt the .value unwrap when $parsed is NOT already an array:
    # PowerShell's collection member-enumeration makes $parsed.value
    # non-null (a same-length array of $null placeholders) even when
    # $parsed is already the real flat array and none of its elements has a
    # literal "value" property -- checking "-isnot [array]" first is what
    # stops that from silently discarding every real record.
    if ($parsed -isnot [array] -and $null -ne $parsed.value) {
        $records = @($parsed.value)
    } else {
        $records = @($parsed)
    }

    return @{ RawText = $rawText; Records = $records }
}

$logPath = "results/policy_scan_log.csv"
if (-not (Test-Path $logPath)) {
    "tool,variant,run,scanned_at,duration_s,n_findings_raw,n_findings_mapped,mc_detected" | Set-Content $logPath
} else {
    $existing = Import-Csv $logPath | Where-Object { $_.variant -eq $Variant -and $_.run -eq "$Run" }
    if ($existing) {
        Write-Error "A row for variant=$Variant run=$Run already exists in $logPath. Remove it first or use a different run number."
        exit 1
    }
}

New-Item -ItemType Directory -Force results/raw | Out-Null

Write-Host "=== Deploying $Variant ==="
bash ./scripts/run_variant.sh $Variant
if ($LASTEXITCODE -ne 0) {
    Write-Error "Deploy failed for $Variant — aborting evaluation"
    exit 1
}

$tfvars = Get-Content "variants/$Variant/terraform.tfvars" -Raw
if ($tfvars -notmatch 'variant_name\s*=\s*"([^"]+)"') {
    Write-Error "No variant_name found in variants/$Variant/terraform.tfvars"
    exit 1
}
$variantName = $matches[1]
$rg = "rg-$variantName"

Write-Host "=== Evaluating $Variant (run $Run) against $rg ==="
$scannedAt = (Get-Date).ToUniversalTime().ToString("o")
$dur = Measure-Command {
    az policy state trigger-scan --resource-group $rg | Out-Null
}

# trigger-scan blocks until the forced scan completes, but state list has been
# observed reading empty immediately after on a slow subscription -- retry
# only while the response is genuinely empty (0 records), since that's the
# one case retrying can actually fix. A non-empty response that doesn't match
# the expected shape is not a timing problem -- retrying won't change it, so
# stop on the first non-empty response regardless of shape and let the check
# below decide whether to fail loudly.
$result = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    $result = Get-PolicyStates -ResourceGroup $rg

    if ($result.Records.Count -gt 0) { break }

    Write-Warning "Attempt $attempt`: 0 records returned (scan likely not yet propagated). Retrying after a short wait..."
    Start-Sleep -Seconds 20
}

$hasComplianceField = $result.Records.Count -gt 0 -and
    ($result.Records[0].PSObject.Properties.Name -contains 'complianceState')

if (-not $hasComplianceField) {
    # RawText may come back as a scalar string or a per-line string array
    # depending on how PowerShell captured the native command's output --
    # force it into one real string before touching Length/Substring so a
    # shape mismatch here can't crash the diagnostic itself.
    $rawJoined = [string]::Join("`n", @($result.RawText))
    $previewLen = [Math]::Min(1000, $rawJoined.Length)

    Write-Host "--- Last raw response (first $previewLen of $($rawJoined.Length) chars) ---"
    if ($previewLen -gt 0) {
        Write-Host $rawJoined.Substring(0, $previewLen)
    } else {
        Write-Host "(empty or null response)"
    }

    if ($result.Records.Count -gt 0) {
        Write-Host "First record's actual property names: $($result.Records[0].PSObject.Properties.Name -join ', ')"
    }

    throw "az policy state list did not return usable compliance records for $rg after 3 attempts. See raw response above."
}

[string]::Join("`n", @($result.RawText)) | Set-Content "results/raw/azpolicy_${variantName}_run${Run}.json"

$nonCompliant = $result.Records | Where-Object { $_.complianceState -match 'noncompliant' }
$mapped = $nonCompliant | Where-Object { $PolicyRuleMap.ContainsKey($_.policyDefinitionReferenceId) }
$mcDetected = ($mapped | ForEach-Object { $PolicyRuleMap[$_.policyDefinitionReferenceId] } | Sort-Object -Unique) -join ";"

"azpolicy,$Variant,$Run,$scannedAt,$($dur.TotalSeconds),$($nonCompliant.Count),$($mapped.Count),$mcDetected" | Add-Content $logPath

Write-Host "Done. Duration: $($dur.TotalSeconds)s | raw non-compliant: $($nonCompliant.Count) | mapped (mc0X-relevant): $($mapped.Count)"
if ($PolicyRuleMap.Count -eq 0) {
    Write-Warning "PolicyRuleMap is empty -- n_findings_mapped will always be 0 until you populate it."
}
Write-Host "Remember to run './scripts/teardown.sh $Variant' when you're finished with it."
