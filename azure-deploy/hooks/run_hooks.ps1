<#
.SYNOPSIS
    Runs all deploy hooks and aggregates results.

.DESCRIPTION
    Helper script to execute all deployment hooks in sequence
    and produce a consolidated results report.

.PARAMETER WorkspacePath
    The workspace root path to run hooks against.

.PARAMETER HookType
    Type of hooks to run: pre-deploy, post-deploy, or all.
#>

param(
    [string]$WorkspacePath = (Get-Location).Path,
    [ValidateSet("pre-deploy", "post-deploy", "all")]
    [string]$HookType = "all"
)

$ErrorActionPreference = "Continue"

$hooksDir = $PSScriptRoot
$azureDir = Join-Path $WorkspacePath ".azure"
$resultsPath = Join-Path $azureDir "hook-results.json"

# Ensure .azure directory exists
if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
}

$results = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    hookType = $HookType
    hooks = @()
    allPassed = $true
}

# Define hooks by type
$preDeployHooks = @(
    @{ name = "auth_check"; script = "pre_deploy_auth_check.ps1" },
    @{ name = "manifest_check"; script = "pre_deploy_manifest_check.ps1" },
    @{ name = "env_check"; script = "pre_deploy_env_check.ps1" }
)

$postDeployHooks = @(
    @{ name = "deploy_capture"; script = "post_deploy_capture.ps1" },
    @{ name = "deploy_verify"; script = "post_deploy_verify.ps1" }
)

# Select hooks to run
$hooksToRun = @()
switch ($HookType) {
    "pre-deploy" { $hooksToRun = $preDeployHooks }
    "post-deploy" { $hooksToRun = $postDeployHooks }
    "all" { $hooksToRun = $preDeployHooks + $postDeployHooks }
}

# Run each hook
foreach ($hook in $hooksToRun) {
    $hookPath = Join-Path $hooksDir $hook.script
    
    if (-not (Test-Path $hookPath)) {
        $results.hooks += @{
            name = $hook.name
            status = "skip"
            message = "Hook script not found: $($hook.script)"
        }
        continue
    }
    
    Write-Host "Running hook: $($hook.name)..." -ForegroundColor Cyan
    
    try {
        $hookOutput = & $hookPath -WorkspacePath $WorkspacePath 2>&1
        $hookExitCode = $LASTEXITCODE
        
        # Try to parse JSON output
        $hookResult = $null
        try {
            $hookResult = $hookOutput | ConvertFrom-Json
        }
        catch {
            $hookResult = @{ status = "unknown"; output = $hookOutput }
        }
        
        $status = if ($hookExitCode -eq 0) { "pass" } else { "fail" }
        
        $results.hooks += @{
            name = $hook.name
            status = $status
            exitCode = $hookExitCode
            result = $hookResult
        }
        
        if ($hookExitCode -ne 0) {
            $results.allPassed = $false
            Write-Host "  ❌ FAILED" -ForegroundColor Red
        }
        else {
            Write-Host "  ✅ PASSED" -ForegroundColor Green
        }
    }
    catch {
        $results.hooks += @{
            name = $hook.name
            status = "error"
            message = $_.Exception.Message
        }
        $results.allPassed = $false
        Write-Host "  ❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Write results
$results | ConvertTo-Json -Depth 10 | Set-Content $resultsPath

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Hook Results Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passedCount = ($results.hooks | Where-Object { $_.status -eq "pass" }).Count
$failedCount = ($results.hooks | Where-Object { $_.status -eq "fail" }).Count
$totalCount = $results.hooks.Count

Write-Host "Total: $totalCount | Passed: $passedCount | Failed: $failedCount"

if ($results.allPassed) {
    Write-Host "✅ All hooks passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "❌ Some hooks failed. Check $resultsPath for details." -ForegroundColor Red
    exit 1
}
