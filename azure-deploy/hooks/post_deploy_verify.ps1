<#
.SYNOPSIS
    Post-deploy verify hook - verifies deployment succeeded and runs health checks.

.DESCRIPTION
    Triggered by GitHub Copilot AFTER deployment commands complete.
    Verifies resources deployed and endpoints are healthy.
    Updates deploy-results.json with verification status.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolResult = $inputJson.toolResult
$toolInput = $inputJson.toolInput
$cwd = $inputJson.cwd

# Only verify after deployment-related commands
$deployCommands = @("azd up", "azd deploy", "azd provision")
$isDeployCommand = $false
$command = ""

if ($toolName -eq "run_in_terminal" -or $toolName -eq "bash") {
    $command = $toolInput.command
    foreach ($deployCmd in $deployCommands) {
        if ($command -match [regex]::Escape($deployCmd)) {
            $isDeployCommand = $true
            break
        }
    }
}

# Skip if not a deploy command
if (-not $isDeployCommand) {
    exit 0
}

# Skip if command failed
$exitCode = 0
if ($toolResult) {
    if ($null -ne $toolResult.exitCode) {
        $exitCode = $toolResult.exitCode
    }
    elseif ($toolResult.resultType -ne "success") {
        $exitCode = 1
    }
}

if ($exitCode -ne 0) {
    exit 0
}

$azureDir = Join-Path $cwd ".azure"
$deployResultsPath = Join-Path $azureDir "deploy-results.json"
$deployManifestPath = Join-Path $azureDir "deploy-manifest.md"
$logPath = Join-Path $azureDir "session.log"

# Ensure .azure directory exists
if (-not (Test-Path $azureDir)) {
    exit 0
}

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

# Verification results
$verificationResults = @{
    timestamp = $timestamp
    checks = @()
    endpoints = @()
    allPassed = $false
}

# Check 1: Get deployed resources via azd show
$resourcesCheck = @{
    name = "resources_deployed"
    passed = $false
    message = ""
}

try {
    $showOutput = azd show --output json 2>&1 | ConvertFrom-Json
    if ($showOutput -and $showOutput.services) {
        $resourcesCheck.passed = $true
        $resourcesCheck.message = "Found $($showOutput.services.Count) deployed services"
        
        # Extract endpoints
        foreach ($service in $showOutput.services.PSObject.Properties) {
            $serviceData = $service.Value
            if ($serviceData.endpoint) {
                $verificationResults.endpoints += @{
                    name = $service.Name
                    url = $serviceData.endpoint
                    health = "pending"
                }
            }
        }
    }
    else {
        $resourcesCheck.message = "No services found in azd show output"
    }
}
catch {
    $resourcesCheck.message = "Failed to get resource info: $($_.Exception.Message)"
}

$verificationResults.checks += $resourcesCheck

# Check 2: Health check endpoints
$healthCheck = @{
    name = "health_check"
    passed = $false
    message = ""
}

$healthyEndpoints = 0
$totalEndpoints = $verificationResults.endpoints.Count

foreach ($endpoint in $verificationResults.endpoints) {
    try {
        $response = Invoke-WebRequest -Uri $endpoint.url -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
            $endpoint.health = "healthy"
            $healthyEndpoints++
        }
        else {
            $endpoint.health = "unhealthy (HTTP $($response.StatusCode))"
        }
    }
    catch {
        # Try without /health first, then with /health
        try {
            $healthUrl = $endpoint.url.TrimEnd('/') + "/health"
            $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                $endpoint.health = "healthy"
                $healthyEndpoints++
            }
            else {
                $endpoint.health = "unhealthy (HTTP $($response.StatusCode))"
            }
        }
        catch {
            $endpoint.health = "unreachable"
        }
    }
}

if ($totalEndpoints -eq 0) {
    $healthCheck.passed = $true
    $healthCheck.message = "No endpoints to check (infrastructure only?)"
}
elseif ($healthyEndpoints -eq $totalEndpoints) {
    $healthCheck.passed = $true
    $healthCheck.message = "All $totalEndpoints endpoints healthy"
}
else {
    $healthCheck.message = "$healthyEndpoints of $totalEndpoints endpoints healthy"
}

$verificationResults.checks += $healthCheck

# Calculate overall status
$failedChecks = $verificationResults.checks | Where-Object { -not $_.passed }
$verificationResults.allPassed = ($failedChecks.Count -eq 0)

# Merge with existing results if present
if (Test-Path $deployResultsPath) {
    $existingResults = Get-Content $deployResultsPath | ConvertFrom-Json
    $existingResults | Add-Member -NotePropertyName "verification" -NotePropertyValue $verificationResults -Force
    $existingResults | Add-Member -NotePropertyName "allPassed" -NotePropertyValue $verificationResults.allPassed -Force
    $existingResults | ConvertTo-Json -Depth 10 | Set-Content $deployResultsPath
}
else {
    $verificationResults | ConvertTo-Json -Depth 10 | Set-Content $deployResultsPath
}

# Update manifest with endpoints
if (Test-Path $deployManifestPath) {
    $manifestContent = Get-Content $deployManifestPath -Raw
    
    # Update status if all passed
    if ($verificationResults.allPassed) {
        $manifestContent = $manifestContent -replace "Status\s*\|\s*In Progress", "Status | Deployed"
    }
    
    # Build endpoints table
    if ($verificationResults.endpoints.Count -gt 0) {
        $endpointsTable = "| Service | URL | Health |`n|---------|-----|--------|"
        foreach ($ep in $verificationResults.endpoints) {
            $healthIcon = if ($ep.health -eq "healthy") { "✅" } else { "❌" }
            $endpointsTable += "`n| $($ep.name) | $($ep.url) | $healthIcon $($ep.health) |"
        }
        
        # Replace endpoints section
        $manifestContent = $manifestContent -replace "## Endpoints[\s\S]*?(?=##|$)", "## Endpoints`n`n$endpointsTable`n`n"
    }
    
    Set-Content -Path $deployManifestPath -Value $manifestContent
}

# Log verification
$status = if ($verificationResults.allPassed) { "PASSED" } else { "FAILED" }
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Verification $status - $healthyEndpoints/$totalEndpoints endpoints healthy" | Add-Content -Path $logPath

# Post-tool hook output is ignored by Copilot
exit 0
