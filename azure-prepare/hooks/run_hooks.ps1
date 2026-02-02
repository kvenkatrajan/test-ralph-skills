<#
.SYNOPSIS
    Hook dispatcher for Ralph Wiggum loop.

.DESCRIPTION
    Runs all required hooks and aggregates results.
    Can run a specific hook or all hooks.

.PARAMETER HookName
    Optional. Name of specific hook to run. If not provided, runs all hooks.

.PARAMETER WorkspacePath
    Path to the workspace. Defaults to current directory.

.OUTPUTS
    JSON object with aggregated hook results
#>

param(
    [string]$HookName = "",
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"

$hooksDir = $PSScriptRoot

# Define all hooks
$allHooks = @(
    @{ name = "manifest_check"; blocking = $true },
    @{ name = "infra_lint"; blocking = $true },
    @{ name = "secrets_scan"; blocking = $true },
    @{ name = "dockerfile_lint"; blocking = $false },
    @{ name = "azure_yaml_check"; blocking = $true }
)

$aggregatedResult = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    workspace = $WorkspacePath
    hooks_run = @()
    all_passed = $true
    blocking_failures = @()
    non_blocking_failures = @()
    summary = @{
        total = 0
        passed = 0
        failed = 0
        blocking_failed = 0
    }
}

# Filter hooks if specific one requested
$hooksToRun = if ($HookName) {
    $allHooks | Where-Object { $_.name -eq $HookName }
} else {
    $allHooks
}

foreach ($hook in $hooksToRun) {
    $hookScript = Join-Path $hooksDir "$($hook.name).ps1"
    
    if (Test-Path $hookScript) {
        $aggregatedResult.summary.total++
        
        try {
            $output = & $hookScript -WorkspacePath $WorkspacePath 2>&1
            $hookResult = $output | ConvertFrom-Json
            
            $aggregatedResult.hooks_run += $hookResult
            
            if ($hookResult.status -eq "pass") {
                $aggregatedResult.summary.passed++
            } else {
                $aggregatedResult.summary.failed++
                $aggregatedResult.all_passed = $false
                
                if ($hookResult.blocking) {
                    $aggregatedResult.summary.blocking_failed++
                    $aggregatedResult.blocking_failures += @{
                        hook = $hookResult.hook
                        error = $hookResult.error
                        fix_scope = $hookResult.fix_scope
                    }
                } else {
                    $aggregatedResult.non_blocking_failures += @{
                        hook = $hookResult.hook
                        error = $hookResult.error
                        fix_scope = $hookResult.fix_scope
                    }
                }
            }
        }
        catch {
            $aggregatedResult.summary.failed++
            $aggregatedResult.all_passed = $false
            
            if ($hook.blocking) {
                $aggregatedResult.summary.blocking_failed++
                $aggregatedResult.blocking_failures += @{
                    hook = $hook.name
                    error = "Hook execution failed: $($_.Exception.Message)"
                    fix_scope = @()
                }
            }
        }
    } else {
        Write-Warning "Hook script not found: $hookScript"
    }
}

# Write results to file
$resultsPath = Join-Path $WorkspacePath ".azure" "hook-results.json"
$azureDir = Join-Path $WorkspacePath ".azure"

if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
}

$aggregatedResult | ConvertTo-Json -Depth 10 | Set-Content $resultsPath

# Output to console
Write-Output ($aggregatedResult | ConvertTo-Json -Depth 10)

# Exit with appropriate code
if ($aggregatedResult.summary.blocking_failed -gt 0) {
    exit 1
}
exit 0
