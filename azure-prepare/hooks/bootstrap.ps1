<#
.SYNOPSIS
    Copies hooks infrastructure to workspace to enable Ralph Wiggum loop.

.DESCRIPTION
    This script must be run BEFORE any other azure-prepare operations.
    It copies hooks.json and the hooks directory to the workspace,
    enabling the CLI's native hook system to enforce validations.
    Hooks are installed to .github/hooks/azure-prepare/ to avoid conflicts.

.PARAMETER WorkspacePath
    Path to the workspace. Defaults to current directory.

.EXAMPLE
    & bootstrap.ps1 -WorkspacePath "C:\myproject"
#>

param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

# Get skill directory (parent of hooks directory)
$skillDir = Split-Path -Parent $PSScriptRoot

# Paths - use .github/hooks/azure-prepare directory for skill isolation
$githubDir = Join-Path $WorkspacePath ".github"
$hooksBaseDir = Join-Path $githubDir "hooks"
$destHooksDir = Join-Path $hooksBaseDir "azure-prepare"
$sourceHooksJson = Join-Path $skillDir "hooks.json"
$sourceHooksDir = Join-Path $skillDir "hooks"
# Main hooks.json in .github/ that merges all skill hooks
$destHooksJson = Join-Path $githubDir "hooks.json"

# Create .github directory if needed
if (-not (Test-Path $githubDir)) {
    New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
    Write-Host "✓ Created .github directory"
}

# Create .github/hooks directory if needed
if (-not (Test-Path $hooksBaseDir)) {
    New-Item -ItemType Directory -Path $hooksBaseDir -Force | Out-Null
    Write-Host "✓ Created .github/hooks directory"
}

# Create .github/hooks/azure-prepare directory if needed
if (-not (Test-Path $destHooksDir)) {
    New-Item -ItemType Directory -Path $destHooksDir -Force | Out-Null
    Write-Host "✓ Created .github/hooks/azure-prepare directory"
}

# Copy hooks directory contents to skill-specific folder
if (Test-Path $sourceHooksDir) {
    # Copy all hook scripts to .github/hooks/azure-prepare/
    Get-ChildItem $sourceHooksDir -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $destHooksDir -Force
    }
    Write-Host "✓ Copied hook scripts to .github/hooks/azure-prepare/"
} else {
    Write-Error "hooks directory not found at $sourceHooksDir"
    exit 1
}

# Merge hooks.json with existing (if present)
if (Test-Path $sourceHooksJson) {
    $sourceHooks = Get-Content $sourceHooksJson | ConvertFrom-Json
    
    if (Test-Path $destHooksJson) {
        # Merge with existing hooks.json
        Write-Host "  Merging with existing hooks.json..." -ForegroundColor Yellow
        $existingHooks = Get-Content $destHooksJson | ConvertFrom-Json
        
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
        
        $existingHooks | ConvertTo-Json -Depth 10 | Set-Content $destHooksJson
        Write-Host "✓ Merged hooks.json"
    }
    else {
        # No existing file, just copy
        Copy-Item $sourceHooksJson -Destination $destHooksJson -Force
        Write-Host "✓ Copied hooks.json to .github/"
    }
} else {
    Write-Error "hooks.json not found at $sourceHooksJson"
    exit 1
}

# Create .azure directory if needed
$azureDir = Join-Path $WorkspacePath ".azure"
if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
    Write-Host "✓ Created .azure directory"
}

Write-Host ""
Write-Host "Ralph Wiggum loop hooks installed successfully."
Write-Host "Location: .github/hooks/azure-prepare/"
Write-Host ""
Write-Host "The following hooks are now active:"
Write-Host "  - sessionStart: session_init"
Write-Host "  - preToolUse: pre_edit_secrets_scan, pre_edit_infra_lint"
Write-Host "  - postToolUse: post_edit_validate"
Write-Host "  - sessionEnd: session_complete"
Write-Host ""
Write-Host "Run '.github/hooks/azure-prepare/run_hooks.ps1' to manually execute all validation hooks."

exit 0
