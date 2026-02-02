<#
.SYNOPSIS
    Session end hook - final verification and deploy manifest status update.

.DESCRIPTION
    Triggered by GitHub Copilot when the agent session ends.
    Runs final verification and updates deploy manifest status.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$cwd = $inputJson.cwd
$timestamp = $inputJson.timestamp
$reason = $inputJson.reason

$azureDir = Join-Path $cwd ".azure"
$deployManifestPath = Join-Path $azureDir "deploy-manifest.md"
$deployResultsPath = Join-Path $azureDir "deploy-results.json"
$logPath = Join-Path $azureDir "session.log"

# Final verification results
$finalResults = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    sessionEndReason = $reason
    finalChecks = @()
    deployComplete = $false
}

# Check 1: Deploy manifest exists
$manifestExists = Test-Path $deployManifestPath
$finalResults.finalChecks += @{
    name = "deploy_manifest_exists"
    passed = $manifestExists
    message = if ($manifestExists) { "Deploy manifest found" } else { "Deploy manifest not found" }
}

# Check 2: Deployment was attempted
$deploymentAttempted = $false
$lastExitCode = -1
if (Test-Path $deployResultsPath) {
    $results = Get-Content $deployResultsPath | ConvertFrom-Json
    if ($results.command) {
        $deploymentAttempted = $true
        $lastExitCode = $results.exitCode
    }
}
$finalResults.finalChecks += @{
    name = "deployment_attempted"
    passed = $deploymentAttempted
    message = if ($deploymentAttempted) { "Deployment was executed (exit code: $lastExitCode)" } else { "No deployment was attempted" }
}

# Check 3: Deployment succeeded
$deploySucceeded = ($deploymentAttempted -and $lastExitCode -eq 0)
$finalResults.finalChecks += @{
    name = "deployment_succeeded"
    passed = $deploySucceeded
    message = if ($deploySucceeded) { "Deployment completed successfully" } else { "Deployment did not succeed" }
}

# Check 4: Verification passed
$verificationPassed = $false
if (Test-Path $deployResultsPath) {
    $results = Get-Content $deployResultsPath | ConvertFrom-Json
    if ($results.verification -and $results.verification.allPassed) {
        $verificationPassed = $true
    }
    elseif ($results.allPassed) {
        $verificationPassed = $true
    }
}
$finalResults.finalChecks += @{
    name = "verification_passed"
    passed = $verificationPassed
    message = if ($verificationPassed) { "All verification checks passed" } else { "Verification incomplete or failed" }
}

# Check 5: Endpoints healthy (if any)
$endpointsHealthy = $true
$healthyCount = 0
$totalCount = 0
if (Test-Path $deployResultsPath) {
    $results = Get-Content $deployResultsPath | ConvertFrom-Json
    if ($results.verification -and $results.verification.endpoints) {
        $totalCount = $results.verification.endpoints.Count
        $healthyCount = ($results.verification.endpoints | Where-Object { $_.health -eq "healthy" }).Count
        $endpointsHealthy = ($healthyCount -eq $totalCount)
    }
}
$finalResults.finalChecks += @{
    name = "endpoints_healthy"
    passed = $endpointsHealthy
    message = if ($totalCount -eq 0) { "No endpoints to verify" } else { "$healthyCount of $totalCount endpoints healthy" }
}

# Determine if deployment is complete
$allPassed = ($finalResults.finalChecks | Where-Object { -not $_.passed }).Count -eq 0
$finalResults.deployComplete = $allPassed

# Update deploy manifest status
if ($manifestExists) {
    $manifestContent = Get-Content $deployManifestPath -Raw
    $newStatus = if ($allPassed) { "Deployed" } elseif ($deploySucceeded) { "Deployed (Unverified)" } else { "Failed" }
    
    # Update Status line
    if ($manifestContent -match "Status\s*\|\s*[\w\s-]+\|") {
        $manifestContent = $manifestContent -replace "Status\s*\|\s*[\w\s-]+\|", "Status | $newStatus |"
        Set-Content -Path $deployManifestPath -Value $manifestContent
    }
    
    # Update hook results section
    $hookResultsSection = @"

## Final Hook Results

| Check | Status | Message |
|-------|--------|---------|
"@
    foreach ($check in $finalResults.finalChecks) {
        $icon = if ($check.passed) { "✅" } else { "❌" }
        $hookResultsSection += "`n| $($check.name) | $icon | $($check.message) |"
    }
    
    # Append or update final results
    if ($manifestContent -match "## Final Hook Results") {
        $manifestContent = $manifestContent -replace "## Final Hook Results[\s\S]*$", $hookResultsSection
    }
    else {
        $manifestContent += "`n$hookResultsSection"
    }
    
    Set-Content -Path $deployManifestPath -Value $manifestContent
}

# Write final results
$finalResults | ConvertTo-Json -Depth 10 | Set-Content $deployResultsPath

# Log session end
$status = if ($allPassed) { "COMPLETE" } elseif ($deploySucceeded) { "DEPLOYED (UNVERIFIED)" } else { "INCOMPLETE" }
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Deploy session ended ($reason) - Status: $status" | Add-Content -Path $logPath

# Session end hook output is ignored by Copilot
exit 0
