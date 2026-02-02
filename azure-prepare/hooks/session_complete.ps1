<#
.SYNOPSIS
    Session end hook - final validation and manifest status update.

.DESCRIPTION
    Triggered by GitHub Copilot when the agent session ends.
    Runs final validation and updates manifest status.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$cwd = $inputJson.cwd
$timestamp = $inputJson.timestamp
$reason = $inputJson.reason

$azureDir = Join-Path $cwd ".azure"
$manifestPath = Join-Path $azureDir "preparation-manifest.md"
$hookResultsPath = Join-Path $azureDir "hook-results.json"

# Final validation results
$finalResults = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    sessionEndReason = $reason
    finalChecks = @()
    prepareReady = $false
}

# Check 1: Manifest completeness
$manifestComplete = $false
if (Test-Path $manifestPath) {
    $content = Get-Content $manifestPath -Raw
    $requiredSections = @("## Requirements", "## Components", "## Recipe", "## Architecture", "## Generated Files")
    $missingSections = $requiredSections | Where-Object { $content -notmatch [regex]::Escape($_) }
    
    $manifestComplete = $missingSections.Count -eq 0
    $finalResults.finalChecks += @{
        name = "manifest_complete"
        passed = $manifestComplete
        message = if ($manifestComplete) { "All required sections present" } else { "Missing: $($missingSections -join ', ')" }
    }
}
else {
    $finalResults.finalChecks += @{
        name = "manifest_complete"
        passed = $false
        message = "Manifest not found"
    }
}

# Check 2: Infrastructure exists
$infraPath = Join-Path $cwd "infra"
$infraExists = Test-Path $infraPath
$infraFiles = if ($infraExists) { 
    Get-ChildItem -Path $infraPath -Filter "*.bicep" -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -Path $infraPath -Filter "*.tf" -Recurse -ErrorAction SilentlyContinue
} else { @() }

$finalResults.finalChecks += @{
    name = "infrastructure_files"
    passed = $infraFiles.Count -gt 0
    message = if ($infraFiles.Count -gt 0) { "Found $($infraFiles.Count) IaC files" } else { "No infrastructure files found" }
}

# Check 3: No secrets in generated files
$secretsFound = $false
$filesToScan = @()
if ($infraExists) {
    $filesToScan += Get-ChildItem -Path $infraPath -Recurse -File -ErrorAction SilentlyContinue
}
$azureYaml = Join-Path $cwd "azure.yaml"
if (Test-Path $azureYaml) {
    $filesToScan += Get-Item $azureYaml
}

foreach ($file in $filesToScan) {
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "AccountKey=[A-Za-z0-9+/=]{88}" -or 
        $content -match "-----BEGIN.*PRIVATE KEY-----" -or
        $content -match "(?i)(password|secret|apikey)\s*[=:]\s*['\"][A-Za-z0-9]{16,}['\"]") {
        $secretsFound = $true
        break
    }
}

$finalResults.finalChecks += @{
    name = "no_secrets"
    passed = -not $secretsFound
    message = if ($secretsFound) { "Hardcoded secrets detected - fix before deployment" } else { "No hardcoded secrets" }
}

# Determine if prepare-ready
$allPassed = ($finalResults.finalChecks | Where-Object { -not $_.passed }).Count -eq 0
$finalResults.prepareReady = $allPassed

# Update manifest status
if (Test-Path $manifestPath) {
    $manifestContent = Get-Content $manifestPath -Raw
    $newStatus = if ($allPassed) { "Prepare-Ready" } else { "Incomplete" }
    
    # Update Status line
    if ($manifestContent -match "Status:\s*\w+") {
        $manifestContent = $manifestContent -replace "Status:\s*\w+", "Status: $newStatus"
        Set-Content -Path $manifestPath -Value $manifestContent
    }
}

# Write final results
$finalResults | ConvertTo-Json -Depth 10 | Set-Content $hookResultsPath

# Log session end
$logPath = Join-Path $azureDir "session.log"
$status = if ($allPassed) { "READY" } else { "INCOMPLETE" }
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Session ended ($reason) - Status: $status" | Add-Content -Path $logPath

# Session end hook output is ignored by Copilot
exit 0
