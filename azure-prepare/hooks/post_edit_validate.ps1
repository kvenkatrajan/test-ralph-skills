<#
.SYNOPSIS
    Post-tool use hook - runs full validation after edits complete.

.DESCRIPTION
    Triggered by GitHub Copilot AFTER any tool completes.
    Runs validation and updates manifest with results.
    Output is ignored but logs are written for the agent to reference.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolResult = $inputJson.toolResult
$cwd = $inputJson.cwd

# Only validate after edit operations
if ($toolName -notin @("edit", "create", "write_file", "create_file", "replace_string_in_file", "bash")) {
    exit 0
}

# Only proceed if the tool succeeded
if ($toolResult.resultType -ne "success") {
    exit 0
}

$azureDir = Join-Path $cwd ".azure"
$manifestPath = Join-Path $azureDir "preparation-manifest.md"
$hookResultsPath = Join-Path $azureDir "hook-results.json"

# Ensure .azure directory exists
if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
}

# Run validation checks
$validationResults = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    trigger = "post_edit"
    toolName = $toolName
    checks = @()
}

# Check 1: Manifest exists
$manifestCheck = @{
    name = "manifest_exists"
    passed = (Test-Path $manifestPath)
    message = if (Test-Path $manifestPath) { "Manifest found" } else { "Manifest not found at .azure/preparation-manifest.md" }
}
$validationResults.checks += $manifestCheck

# Check 2: Infra directory exists (if we're past initial steps)
$infraPath = Join-Path $cwd "infra"
$infraCheck = @{
    name = "infra_directory"
    passed = (Test-Path $infraPath)
    message = if (Test-Path $infraPath) { "Infrastructure directory found" } else { "No infra/ directory yet" }
}
$validationResults.checks += $infraCheck

# Check 3: Scan for secrets in recently edited files
$secretsFound = $false
$secretsMessage = "No hardcoded secrets detected"

$recentFiles = Get-ChildItem -Path $cwd -Recurse -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) } |
    Where-Object { $_.Extension -in @(".bicep", ".tf", ".yaml", ".yml", ".json", ".ps1", ".sh", ".py", ".js", ".ts", ".cs") }

foreach ($file in $recentFiles) {
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "AccountKey=[A-Za-z0-9+/=]{88}" -or 
        $content -match "-----BEGIN.*PRIVATE KEY-----" -or
        $content -match "(?i)(password|secret)\s*[=:]\s*['\"][^'\"]{8,}['\"]") {
        $secretsFound = $true
        $secretsMessage = "Potential secret in: $($file.Name)"
        break
    }
}

$secretsCheck = @{
    name = "secrets_scan"
    passed = -not $secretsFound
    message = $secretsMessage
}
$validationResults.checks += $secretsCheck

# Calculate overall status
$allPassed = ($validationResults.checks | Where-Object { -not $_.passed }).Count -eq 0
$validationResults.allPassed = $allPassed

# Write results to file
$validationResults | ConvertTo-Json -Depth 10 | Set-Content $hookResultsPath

# Update manifest with latest hook results if it exists
if (Test-Path $manifestPath) {
    $manifestContent = Get-Content $manifestPath -Raw
    
    # Update the Hook Results section timestamp
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    
    # Log to session log
    $logPath = Join-Path $azureDir "session.log"
    $passedCount = ($validationResults.checks | Where-Object { $_.passed }).Count
    $totalCount = $validationResults.checks.Count
    "$timestamp : Post-edit validation: $passedCount/$totalCount checks passed" | Add-Content -Path $logPath
}

# Post-tool hook output is ignored by Copilot
exit 0
