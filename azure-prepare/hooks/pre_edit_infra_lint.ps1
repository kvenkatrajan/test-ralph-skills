<#
.SYNOPSIS
    Pre-tool use hook - validates IaC syntax before allowing infra edits.

.DESCRIPTION
    Triggered by GitHub Copilot BEFORE edit operations on infra/ files.
    Checks that edits to Bicep/Terraform maintain valid syntax.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $inputJson.toolName
$toolArgs = $inputJson.toolArgs | ConvertFrom-Json -ErrorAction SilentlyContinue
$cwd = $inputJson.cwd

# Only check edit operations
if ($toolName -notin @("edit", "create", "write_file", "create_file", "replace_string_in_file")) {
    exit 0
}

# Get the file path being edited
$filePath = $null
if ($toolArgs.path) { $filePath = $toolArgs.path }
elseif ($toolArgs.filePath) { $filePath = $toolArgs.filePath }
elseif ($toolArgs.file) { $filePath = $toolArgs.file }

if (-not $filePath) {
    exit 0
}

# Only check infra files
if ($filePath -notmatch "infra[/\\].*\.(bicep|tf)$") {
    exit 0
}

# For Bicep files, check basic syntax of new content
if ($filePath -match "\.bicep$") {
    $content = $null
    if ($toolArgs.content) { $content = $toolArgs.content }
    elseif ($toolArgs.newString) { $content = $toolArgs.newString }
    
    if ($content) {
        # Basic Bicep syntax checks
        $issues = @()
        
        # Check for unclosed braces
        $openBraces = ([regex]::Matches($content, '\{')).Count
        $closeBraces = ([regex]::Matches($content, '\}')).Count
        if ($openBraces -ne $closeBraces) {
            $issues += "Unbalanced braces (open: $openBraces, close: $closeBraces)"
        }
        
        # Check for param without type
        if ($content -match "param\s+\w+\s*=") {
            $issues += "Parameter missing type annotation (use 'param name type = value')"
        }
        
        # Check for resource without API version
        if ($content -match "resource\s+\w+\s+'[^']+'\s*=" -and $content -notmatch "resource\s+\w+\s+'[^']+@[^']+'\s*=") {
            $issues += "Resource declaration missing API version"
        }
        
        if ($issues.Count -gt 0) {
            $output = @{
                permissionDecision = "deny"
                permissionDecisionReason = "Bicep syntax issues: $($issues -join '; ')"
            }
            $output | ConvertTo-Json -Compress
            exit 0
        }
    }
}

# For Terraform files, check basic syntax
if ($filePath -match "\.tf$") {
    $content = $null
    if ($toolArgs.content) { $content = $toolArgs.content }
    elseif ($toolArgs.newString) { $content = $toolArgs.newString }
    
    if ($content) {
        $issues = @()
        
        # Check for unclosed braces
        $openBraces = ([regex]::Matches($content, '\{')).Count
        $closeBraces = ([regex]::Matches($content, '\}')).Count
        if ($openBraces -ne $closeBraces) {
            $issues += "Unbalanced braces"
        }
        
        # Check for missing = in assignments
        if ($content -match '^\s*\w+\s+"' -and $content -notmatch '^\s*\w+\s*=\s*"') {
            $issues += "Missing = in assignment"
        }
        
        if ($issues.Count -gt 0) {
            $output = @{
                permissionDecision = "deny"
                permissionDecisionReason = "Terraform syntax issues: $($issues -join '; ')"
            }
            $output | ConvertTo-Json -Compress
            exit 0
        }
    }
}

# Allow the edit
exit 0
