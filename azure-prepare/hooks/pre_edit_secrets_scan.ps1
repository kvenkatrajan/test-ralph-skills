<#
.SYNOPSIS
    Pre-tool use hook - blocks edits that would introduce hardcoded secrets.

.DESCRIPTION
    Triggered by GitHub Copilot BEFORE any tool use (edit, create, bash).
    Returns permissionDecision to allow or deny the operation.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolArgs = $inputJson.toolArgs | ConvertFrom-Json -ErrorAction SilentlyContinue
$cwd = $inputJson.cwd

# Only check edit and create operations
if ($toolName -notin @("edit", "create", "write_file", "create_file", "replace_string_in_file")) {
    # Allow non-edit tools
    exit 0
}

# Get the content being written
$contentToCheck = $null

if ($toolArgs.content) {
    $contentToCheck = $toolArgs.content
}
elseif ($toolArgs.newString) {
    $contentToCheck = $toolArgs.newString
}
elseif ($toolArgs.text) {
    $contentToCheck = $toolArgs.text
}

if (-not $contentToCheck) {
    # No content to check, allow
    exit 0
}

# Secret patterns to detect
$secretPatterns = @(
    @{ name = "Azure Storage Key"; pattern = "AccountKey=[A-Za-z0-9+/=]{88}" },
    @{ name = "API Key"; pattern = "(?i)(api[_-]?key|apikey)\s*[=:]\s*['\"][A-Za-z0-9]{20,}['\"]" },
    @{ name = "Password"; pattern = "(?i)(password|passwd|pwd)\s*[=:]\s*['\"][^'\"]{8,}['\"]" },
    @{ name = "Bearer Token"; pattern = "Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+" },
    @{ name = "Private Key"; pattern = "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----" },
    @{ name = "Client Secret"; pattern = "(?i)client[_-]?secret\s*[=:]\s*['\"][A-Za-z0-9~._-]{34,}['\"]" },
    @{ name = "Connection String"; pattern = "(?i)(Server|Data Source)=[^;]+;.*(Password|Pwd)=[^;]+" }
)

# Check content for secrets
foreach ($pattern in $secretPatterns) {
    if ($contentToCheck -match $pattern.pattern) {
        # DENY - secret detected
        $output = @{
            permissionDecision = "deny"
            permissionDecisionReason = "Hardcoded secret detected: $($pattern.name). Use Key Vault or environment variables instead."
        }
        $output | ConvertTo-Json -Compress
        exit 0
    }
}

# No secrets found - allow (by not outputting anything, or explicit allow)
# Outputting nothing means allow
exit 0
