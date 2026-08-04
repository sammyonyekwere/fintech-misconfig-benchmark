
# Usage: pwsh harness/deployed_state_policy_scan.ps1 <variant> <run>

param(
    [Parameter(Mandatory, Position=0)]
    [string]$Variant,

    [Parameter(Mandatory, Position=1)]
    [int]$Run
)

# --- mc0X -> Azure Policy mapping -------------------------------------------------
# Built the same empirical way as results/rule_map.json: diff each variant's
# non-compliant policyDefinitionReferenceId set against the hardened baseline
# (results/raw/azpolicy_hardenedtest2_run2.json), verified against real data
# for all 10 vuln-0X variants plus all 3 mixed-seed variants and
# noisy-compliant (zero false positives, every mixed-variant detection
# matched its exact ground-truth flags with no spillover). mc02, mc04, mc05,
# mc09, mc10 showed zero new non-compliant policies -- confirmed no MCSB
# coverage, consistent with (or in mc04/mc09's case, narrower than) the
# static and what-if tiers. No entries added for those (nothing to map).
$PolicyRuleMap = @{
    "storagedisallowpublicaccess"                                             = "mc01_public_storage"
    "publicnetworkaccessonazuresqldatabaseshouldbedisabledmonitoringeffect"   = "mc03_sql_public"
    "functionappenforcehttpsmonitoring"                                       = "mc06_no_https"
    "securetransfertostorageaccountmonitoring"                                = "mc06_no_https"
    "diagnosticslogsinkeyvaultmonitoring"                                     = "mc07_logging_disabled"
    "keyvaultsshouldhavepurgeprotectionenabledmonitoringeffect"               = "mc08_no_cmk"
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
# Pass $Run through explicitly -- run_variant.sh defaults to run 1 when the
# second argument is omitted, which would make repeated invocations (or
# policy_whatif_scan.ps1 targeting the same variant) silently overwrite
# each other's results/logs/<variant>_run<N>.log via `tee`.
bash ./scripts/run_variant.sh $Variant $Run
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
