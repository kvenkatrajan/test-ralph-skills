<#
.SYNOPSIS
    Post-deploy capture hook - captures deployment output and detects errors.

.DESCRIPTION
    Triggered by GitHub Copilot AFTER any deployment tool completes.
    Captures output to log file and updates deploy manifest.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolResult = $inputJson.toolResult
$toolInput = $inputJson.toolInput
$cwd = $inputJson.cwd

# Only capture for deployment-related commands
$deployCommands = @("azd up", "azd deploy", "azd provision", "az deployment", "terraform apply")
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

$azureDir = Join-Path $cwd ".azure"
$deployOutputPath = Join-Path $azureDir "deploy-output.log"
$deployResultsPath = Join-Path $azureDir "deploy-results.json"
$deployManifestPath = Join-Path $azureDir "deploy-manifest.md"
$logPath = Join-Path $azureDir "session.log"

# Ensure .azure directory exists
if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
}

# Extract output from tool result
$output = ""
$exitCode = -1

if ($toolResult) {
    if ($toolResult.output) {
        $output = $toolResult.output
    }
    elseif ($toolResult.stdout) {
        $output = $toolResult.stdout
    }
    
    if ($null -ne $toolResult.exitCode) {
        $exitCode = $toolResult.exitCode
    }
    elseif ($toolResult.resultType -eq "success") {
        $exitCode = 0
    }
    else {
        $exitCode = 1
    }
}

# Capture output to log file
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
$logEntry = @"
================================================================================
Deployment Capture: $timestamp
Command: $command
Exit Code: $exitCode
================================================================================
$output
================================================================================

"@
Add-Content -Path $deployOutputPath -Value $logEntry

# Detect common errors in output
$errors = @()
$errorPatterns = @{
    "not authenticated" = "Authentication required - run 'azd auth login'"
    "quota exceeded" = "Resource quota exceeded - request increase or change region"
    "already exists" = "Resource name conflict - use a different name"
    "permission denied" = "Insufficient permissions - check RBAC"
    "failed to provision" = "Provisioning failed - check Bicep/Terraform errors"
    "failed to deploy" = "Deployment failed - check application build errors"
    "package failed" = "Package build failed - check Dockerfile"
}

foreach ($pattern in $errorPatterns.Keys) {
    if ($output -match $pattern) {
        $errors += @{
            pattern = $pattern
            suggestion = $errorPatterns[$pattern]
        }
    }
}

# Read current attempt number from manifest
$currentAttempt = 1
if (Test-Path $deployManifestPath) {
    $manifestContent = Get-Content $deployManifestPath -Raw
    if ($manifestContent -match "Attempt\s*\|\s*(\d+)") {
        $currentAttempt = [int]$matches[1]
    }
}

# Build results object
$results = @{
    timestamp = $timestamp
    attempt = $currentAttempt
    command = $command
    exitCode = $exitCode
    success = ($exitCode -eq 0)
    errors = $errors
    outputLength = $output.Length
}

# Write results
$results | ConvertTo-Json -Depth 10 | Set-Content $deployResultsPath

# Update manifest with deployment attempt
if (Test-Path $deployManifestPath) {
    $manifestContent = Get-Content $deployManifestPath -Raw
    
    # Update last deploy time
    $manifestContent = $manifestContent -replace "Last Deploy\s*\|\s*[^\|]+\|", "Last Deploy | $timestamp |"
    
    # Update exit code
    $manifestContent = $manifestContent -replace "Exit Code\s*\|\s*[^\|]+\|", "Exit Code | $exitCode |"
    
    Set-Content -Path $deployManifestPath -Value $manifestContent
}

# Log capture
$resultText = if ($exitCode -eq 0) { "SUCCESS" } else { "FAILED (errors: $($errors.Count))" }
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Deploy capture - $command - Exit: $exitCode - $resultText" | Add-Content -Path $logPath

# Post-tool hook output is ignored by Copilot
exit 0
