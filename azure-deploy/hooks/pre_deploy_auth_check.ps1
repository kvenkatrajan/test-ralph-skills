<#
.SYNOPSIS
    Pre-deploy auth check - blocks deployment if not authenticated to Azure.

.DESCRIPTION
    Triggered by GitHub Copilot BEFORE any deployment tool is used.
    Checks if user is authenticated to Azure via azd or az CLI.
    Returns permissionDecision: deny if not authenticated.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolInput = $inputJson.toolInput

# Only check for deployment-related commands
$deployCommands = @("azd up", "azd deploy", "azd provision", "az deployment", "terraform apply", "bicep deploy")
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

# Check Azure authentication
$authenticated = $false
$authMethod = ""
$authError = ""

# Check azd auth status
try {
    $azdAuthOutput = azd auth login --check-status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $authenticated = $true
        $authMethod = "azd"
    }
}
catch {
    # azd auth check failed
}

# Fallback to az CLI check
if (-not $authenticated) {
    try {
        $azAccount = az account show --query "user.name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $azAccount) {
            $authenticated = $true
            $authMethod = "az"
        }
    }
    catch {
        # az auth check failed
    }
}

if (-not $authenticated) {
    # Block the operation
    $result = @{
        permissionDecision = "deny"
        permissionDecisionReason = "Not authenticated to Azure. Run 'azd auth login' or 'az login' first before deploying."
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    
    # Log to session log
    $cwd = $inputJson.cwd
    $logPath = Join-Path $cwd ".azure" "session.log"
    if (Test-Path (Split-Path $logPath)) {
        "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): BLOCKED - Auth check failed for command: $($toolInput.command)" | Add-Content -Path $logPath
    }
    
    exit 0
}

# Authenticated - allow the operation
$cwd = $inputJson.cwd
$logPath = Join-Path $cwd ".azure" "session.log"
if (Test-Path (Split-Path $logPath)) {
    "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Auth check passed ($authMethod)" | Add-Content -Path $logPath
}

exit 0
