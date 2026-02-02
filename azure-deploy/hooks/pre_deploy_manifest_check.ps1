<#
.SYNOPSIS
    Pre-deploy manifest check - blocks deployment if manifest not validated by azure-validate skill.

.DESCRIPTION
    Triggered by GitHub Copilot BEFORE any deployment tool is used.
    Checks if .azure/preparation-manifest.md exists with:
    - Status: Validated
    - Validated By: azure-validate
    - Validation Checksum (proves azure-validate was actually run)
    Returns permissionDecision: deny if not properly validated.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolInput = $inputJson.toolInput
$cwd = $inputJson.cwd

# Only check for deployment-related commands
$deployCommands = @("azd up", "azd deploy", "azd provision", "az deployment", "terraform apply", "bicep deploy")
$isDeployCommand = $false

if ($toolName -eq "run_in_terminal" -or $toolName -eq "bash" -or $toolName -eq "powershell") {
    $command = $toolInput.command
    foreach ($deployCmd in $deployCommands) {
        if ($command -match [regex]::Escape($deployCmd)) {
            $isDeployCommand = $true
            break
        }
    }
}

# Skip check if not a deploy command
if (-not $isDeployCommand) {
    exit 0
}

$azureDir = Join-Path $cwd ".azure"
$manifestPath = Join-Path $azureDir "preparation-manifest.md"
$logPath = Join-Path $azureDir "session.log"

# Check if manifest exists
if (-not (Test-Path $manifestPath)) {
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "Preparation manifest not found at .azure/preparation-manifest.md. Run azure-prepare skill first."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    if (Test-Path $azureDir) {
        "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - Manifest not found" | Add-Content -Path $logPath
    }
    exit 0
}

# Check manifest content
$manifestContent = Get-Content $manifestPath -Raw

# Check 1: Status must be Validated
$isValidated = $manifestContent -match "Status\s*\|\s*Validated"

if (-not $isValidated) {
    $currentStatus = "Unknown"
    if ($manifestContent -match "Status\s*\|\s*([^\|]+)") {
        $currentStatus = $matches[1].Trim()
    }
    
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "Manifest status is '$currentStatus', not 'Validated'. Run azure-validate skill first before deploying."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - Manifest status is '$currentStatus' (requires 'Validated')" | Add-Content -Path $logPath
    exit 0
}

# Check 2: Must have "Validated By: azure-validate" - proves the skill was invoked
$hasValidatedBy = $manifestContent -match "Validated By\s*\|\s*azure-validate"

if (-not $hasValidatedBy) {
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "Manifest missing 'Validated By: azure-validate' field. The azure-validate skill must be invoked to validate the deployment. Manual status changes are not accepted."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - Missing 'Validated By: azure-validate' (skill was not invoked)" | Add-Content -Path $logPath
    exit 0
}

# Check 3: Must have a validation checksum
$hasChecksum = $manifestContent -match "Validation Checksum\s*\|\s*[a-f0-9]{8}"

if (-not $hasChecksum) {
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "Manifest missing validation checksum. The azure-validate skill must be properly invoked to generate a checksum. Re-run azure-validate."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - Missing validation checksum" | Add-Content -Path $logPath
    exit 0
}

# All checks passed - allow the operation
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Manifest check passed (status: Validated, validated by: azure-validate, checksum: present)" | Add-Content -Path $logPath
exit 0
