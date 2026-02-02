<#
.SYNOPSIS
    Scans generated files for hardcoded secrets.

.DESCRIPTION
    This hook scans all generated files for potential hardcoded secrets,
    API keys, connection strings, and other sensitive data.

.OUTPUTS
    JSON object with hook result
#>

param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"

$result = @{
    hook = "secrets_scan"
    status = "pass"
    blocking = $true
    error = $null
    fix_scope = @()
    details = @{
        files_scanned = 0
        secrets_found = @()
    }
}

# Patterns for secret detection (using single quotes to avoid PowerShell string interpolation)
$secretPatterns = @(
    @{ name = "Azure Storage Key"; pattern = 'DefaultEndpointsProtocol=https;AccountName=\w+;AccountKey=[A-Za-z0-9+/=]{88}' },
    @{ name = "Azure Connection String"; pattern = 'AccountKey=[A-Za-z0-9+/=]{88}' },
    @{ name = "API Key Pattern"; pattern = '(?i)(api[_\-]?key|apikey)\s*[=:]\s*[''"][A-Za-z0-9]{20,}[''""]' },
    @{ name = "Password in Config"; pattern = '(?i)(password|passwd|pwd)\s*[=:]\s*[''"][^''"]{8,}[''""]' },
    @{ name = "Bearer Token"; pattern = 'Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+' },
    @{ name = "Private Key"; pattern = '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' },
    @{ name = "Azure AD Client Secret"; pattern = '(?i)client[_\-]?secret\s*[=:]\s*[''"][A-Za-z0-9~._\-]{34,}[''""]' },
    @{ name = "SQL Connection String"; pattern = '(?i)(Server|Data Source)=[^;]+;.*(Password|Pwd)=[^;]+' },
    @{ name = "Generic Secret"; pattern = '(?i)secret\s*[=:]\s*[''"][A-Za-z0-9]{16,}[''""]' },
    @{ name = "Hardcoded GUID as Secret"; pattern = '(?i)(key|secret|token)\s*[=:]\s*[''"][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[''""]' }
)

# File extensions to scan
$extensionsToScan = @(".bicep", ".tf", ".yaml", ".yml", ".json", ".ps1", ".sh", ".py", ".js", ".ts", ".cs", ".config", ".env")

# Directories to scan
$dirsToScan = @("infra", "src", ".azure")

$filesWithSecrets = @{}

foreach ($dir in $dirsToScan) {
    $dirPath = Join-Path $WorkspacePath $dir
    
    if (Test-Path $dirPath) {
        $files = Get-ChildItem -Path $dirPath -Recurse -File -ErrorAction SilentlyContinue | 
                 Where-Object { $extensionsToScan -contains $_.Extension }
        
        foreach ($file in $files) {
            $result.details.files_scanned++
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            
            if ($content) {
                foreach ($pattern in $secretPatterns) {
                    if ($content -match $pattern.pattern) {
                        $relativePath = $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
                        
                        if (-not $filesWithSecrets.ContainsKey($relativePath)) {
                            $filesWithSecrets[$relativePath] = @()
                        }
                        
                        $filesWithSecrets[$relativePath] += $pattern.name
                        
                        # Find line number
                        $lines = $content -split "`n"
                        for ($i = 0; $i -lt $lines.Count; $i++) {
                            if ($lines[$i] -match $pattern.pattern) {
                                $result.details.secrets_found += @{
                                    file = $relativePath
                                    line = $i + 1
                                    type = $pattern.name
                                }
                                break
                            }
                        }
                    }
                }
            }
        }
    }
}

# Set result based on findings
if ($result.details.secrets_found.Count -gt 0) {
    $result.status = "fail"
    $result.error = "Found $($result.details.secrets_found.Count) potential hardcoded secret(s)"
    $result.fix_scope = $filesWithSecrets.Keys | ForEach-Object { $_ }
}

Write-Output ($result | ConvertTo-Json -Depth 10)

if ($result.status -eq "fail") {
    exit 1
}
exit 0
