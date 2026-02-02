<#
.SYNOPSIS
    Pre-deploy environment check - blocks deployment if environment not configured.

.DESCRIPTION
    Triggered by GitHub Copilot BEFORE any deployment tool is used.
    Checks if azd environment is selected and configured.
    Returns permissionDecision: deny if environment not ready.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolInput = $inputJson.toolInput
$cwd = $inputJson.cwd

# Only check for deployment-related commands
$deployCommands = @("azd up", "azd deploy", "azd provision")
$isDeployCommand = $false

if ($toolName -eq "run_in_terminal" -or $toolName -eq "bash") {
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
$logPath = Join-Path $azureDir "session.log"

# Check if azure.yaml exists (required for azd)
$azureYamlPath = Join-Path $cwd "azure.yaml"
if (-not (Test-Path $azureYamlPath)) {
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "azure.yaml not found. The application must be prepared for Azure deployment first. Run azure-prepare skill."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    if (Test-Path $azureDir) {
        "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - azure.yaml not found" | Add-Content -Path $logPath
    }
    exit 0
}

# Check if azd environment exists
$envCheckPassed = $false
$envName = ""

try {
    # Get current environment
    $envOutput = azd env list --output json 2>&1 | ConvertFrom-Json
    
    if ($envOutput -and $envOutput.Count -gt 0) {
        # Find the default environment
        $defaultEnv = $envOutput | Where-Object { $_.IsDefault -eq $true }
        if ($defaultEnv) {
            $envCheckPassed = $true
            $envName = $defaultEnv.Name
        }
        else {
            # No default but environments exist
            $envName = $envOutput[0].Name
            $envCheckPassed = $true
        }
    }
}
catch {
    # azd env check failed - might be first deployment
    # Allow to proceed, azd up will create environment
    $envCheckPassed = $true
    $envName = "(will be created)"
}

if (-not $envCheckPassed) {
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "No azd environment configured. Run 'azd env new <name>' to create one first."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    if (Test-Path $azureDir) {
        "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - No azd environment configured" | Add-Content -Path $logPath
    }
    exit 0
}

# Environment check passed
if (Test-Path $azureDir) {
    "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Environment check passed (env: $envName)" | Add-Content -Path $logPath
}
exit 0
