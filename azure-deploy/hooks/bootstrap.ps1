<#
.SYNOPSIS
    Bootstrap script to install azure-deploy hooks into the workspace.

.DESCRIPTION
    Copies hook scripts and configuration from the skill directory
    to the workspace's .github/hooks directory.

.PARAMETER WorkspacePath
    The root path of the workspace to install hooks into.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspacePath
)

$ErrorActionPreference = "Stop"

Write-Host "Installing azure-deploy hooks to workspace..." -ForegroundColor Cyan

# Determine skill directory (where this script is located)
$skillDir = Split-Path -Parent $PSScriptRoot
$hooksSourceDir = Join-Path $skillDir "hooks"

# Target directories
$githubDir = Join-Path $WorkspacePath ".github"
$hooksBaseDir = Join-Path $githubDir "hooks"
$hooksTargetDir = Join-Path $hooksBaseDir "azure-deploy"

# Create directories
if (-not (Test-Path $githubDir)) {
    New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
    Write-Host "  Created .github directory" -ForegroundColor Green
}

if (-not (Test-Path $hooksBaseDir)) {
    New-Item -ItemType Directory -Path $hooksBaseDir -Force | Out-Null
    Write-Host "  Created .github/hooks directory" -ForegroundColor Green
}

if (-not (Test-Path $hooksTargetDir)) {
    New-Item -ItemType Directory -Path $hooksTargetDir -Force | Out-Null
    Write-Host "  Created .github/hooks/azure-deploy directory" -ForegroundColor Green
}

# Copy/merge hooks.json
$hooksJsonSource = Join-Path $skillDir "hooks.json"
$hooksJsonTarget = Join-Path $githubDir "hooks.json"

if (Test-Path $hooksJsonSource) {
    $sourceHooks = Get-Content $hooksJsonSource | ConvertFrom-Json
    
    if (Test-Path $hooksJsonTarget) {
        # Merge with existing hooks.json
        Write-Host "  Merging with existing hooks.json..." -ForegroundColor Yellow
        $existingHooks = Get-Content $hooksJsonTarget | ConvertFrom-Json
        
        # Merge each hook type (sessionStart, preToolUse, postToolUse, sessionEnd)
        foreach ($hookType in @("sessionStart", "preToolUse", "postToolUse", "sessionEnd")) {
            if ($sourceHooks.hooks.$hookType) {
                if (-not $existingHooks.hooks.$hookType) {
                    $existingHooks.hooks | Add-Member -NotePropertyName $hookType -NotePropertyValue @() -Force
                }
                
                foreach ($newHook in $sourceHooks.hooks.$hookType) {
                    # Check if hook already exists (by bash or powershell path)
                    $exists = $false
                    foreach ($existingHook in $existingHooks.hooks.$hookType) {
                        if ($existingHook.bash -eq $newHook.bash -or $existingHook.powershell -eq $newHook.powershell) {
                            $exists = $true
                            break
                        }
                    }
                    
                    if (-not $exists) {
                        $existingHooks.hooks.$hookType += $newHook
                        Write-Host "    Added hook: $($newHook.comment)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "    Hook already exists: $($newHook.comment)" -ForegroundColor Gray
                    }
                }
            }
        }
        
        $existingHooks | ConvertTo-Json -Depth 10 | Set-Content $hooksJsonTarget
        Write-Host "  Merged hooks.json" -ForegroundColor Green
    }
    else {
        # No existing file, just copy
        Copy-Item -Path $hooksJsonSource -Destination $hooksJsonTarget -Force
        Write-Host "  Copied hooks.json" -ForegroundColor Green
    }
}
else {
    Write-Warning "hooks.json not found at $hooksJsonSource"
}

# Copy all hook scripts
$hookScripts = @(
    "session_init.ps1",
    "session_init.sh",
    "pre_deploy_auth_check.ps1",
    "pre_deploy_auth_check.sh",
    "pre_deploy_manifest_check.ps1",
    "pre_deploy_manifest_check.sh",
    "pre_deploy_env_check.ps1",
    "pre_deploy_env_check.sh",
    "post_deploy_capture.ps1",
    "post_deploy_capture.sh",
    "post_deploy_verify.ps1",
    "post_deploy_verify.sh",
    "session_complete.ps1",
    "session_complete.sh",
    "run_hooks.ps1",
    "run_hooks.sh"
)

foreach ($script in $hookScripts) {
    $source = Join-Path $hooksSourceDir $script
    $target = Join-Path $hooksTargetDir $script
    
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $target -Force
        Write-Host "  Copied $script" -ForegroundColor Green
    }
    else {
        Write-Warning "Hook script not found: $script"
    }
}

# Create .azure directory if it doesn't exist
$azureDir = Join-Path $WorkspacePath ".azure"
if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
    Write-Host "  Created .azure directory" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Hook Installation Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed to:" -ForegroundColor White
Write-Host "  - $hooksJsonTarget" -ForegroundColor Gray
Write-Host "  - $hooksTargetDir\" -ForegroundColor Gray
Write-Host ""
Write-Host "Hooks will be loaded from: .github/hooks/azure-deploy/" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now proceed with deployment." -ForegroundColor Green
