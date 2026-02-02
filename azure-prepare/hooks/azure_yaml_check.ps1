<#
.SYNOPSIS
    Validates azure.yaml structure for AZD projects.

.DESCRIPTION
    This hook validates that azure.yaml exists (for AZD recipe) and contains
    all required fields and proper structure.

.OUTPUTS
    JSON object with hook result
#>

param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"

$result = @{
    hook = "azure_yaml_check"
    status = "pass"
    blocking = $true
    error = $null
    fix_scope = @()
    details = @{
        azure_yaml_exists = $false
        services_defined = @()
        missing_fields = @()
        validation_errors = @()
    }
}

$azureYamlPath = Join-Path $WorkspacePath "azure.yaml"
$manifestPath = Join-Path $WorkspacePath ".azure" "preparation-manifest.md"

# Check if this is an AZD project by checking manifest
$isAzdProject = $false
if (Test-Path $manifestPath) {
    $manifestContent = Get-Content $manifestPath -Raw -ErrorAction SilentlyContinue
    if ($manifestContent -match "(?i)recipe.*azd|selected.*azd") {
        $isAzdProject = $true
    }
}

# If not AZD project, this check is not applicable
if (-not $isAzdProject -and -not (Test-Path $azureYamlPath)) {
    $result.details.azure_yaml_exists = $false
    $result.details.validation_errors += "Not an AZD project - azure.yaml check skipped"
    Write-Output ($result | ConvertTo-Json -Depth 10)
    exit 0
}

# Check if azure.yaml exists
if (-not (Test-Path $azureYamlPath)) {
    $result.status = "fail"
    $result.error = "azure.yaml not found but AZD recipe is selected"
    $result.fix_scope = @("azure.yaml")
    $result.details.azure_yaml_exists = $false
    Write-Output ($result | ConvertTo-Json -Depth 10)
    exit 1
}

$result.details.azure_yaml_exists = $true

# Read and parse azure.yaml
try {
    # Use PowerShell-yaml module if available, otherwise basic parsing
    $content = Get-Content $azureYamlPath -Raw
    
    # Required fields check
    $requiredFields = @("name", "services")
    
    foreach ($field in $requiredFields) {
        if ($content -notmatch "(?m)^$field\s*:") {
            $result.details.missing_fields += $field
        }
    }
    
    # Extract services
    if ($content -match "(?ms)services:\s*\n((?:\s+\w+:.*?\n)+)") {
        $servicesSection = $Matches[1]
        $serviceMatches = [regex]::Matches($servicesSection, "(?m)^\s{2}(\w+):")
        
        foreach ($match in $serviceMatches) {
            $result.details.services_defined += $match.Groups[1].Value
        }
    }
    
    # Validate each service has required fields
    foreach ($service in $result.details.services_defined) {
        # Check for host field
        if ($content -notmatch "(?ms)$service\s*:.*?host\s*:") {
            $result.details.validation_errors += "Service '$service' missing 'host' field"
        }
    }
    
    # Check for project or language field in services
    if ($result.details.services_defined.Count -gt 0) {
        foreach ($service in $result.details.services_defined) {
            $hasProjectOrLanguage = $content -match "(?ms)$service\s*:.*?(project|language)\s*:"
            if (-not $hasProjectOrLanguage) {
                $result.details.validation_errors += "Service '$service' should have 'project' or 'language' field"
            }
        }
    }
    
    # Check for infra configuration
    if ($content -notmatch "(?m)^infra\s*:" -and $content -notmatch "(?m)^\s+infra\s*:") {
        $result.details.validation_errors += "Consider adding 'infra' configuration for custom infrastructure"
    }
}
catch {
    $result.details.validation_errors += "Failed to parse azure.yaml: $($_.Exception.Message)"
}

# Determine final status
if ($result.details.missing_fields.Count -gt 0) {
    $result.status = "fail"
    $result.error = "azure.yaml missing required fields: $($result.details.missing_fields -join ', ')"
    $result.fix_scope = @("azure.yaml")
}
elseif (($result.details.validation_errors | Where-Object { $_ -notmatch "Consider" }).Count -gt 0) {
    $criticalErrors = $result.details.validation_errors | Where-Object { $_ -notmatch "Consider" }
    if ($criticalErrors.Count -gt 0) {
        $result.status = "fail"
        $result.error = "azure.yaml validation failed: $($criticalErrors[0])"
        $result.fix_scope = @("azure.yaml")
    }
}

Write-Output ($result | ConvertTo-Json -Depth 10)

if ($result.status -eq "fail") {
    exit 1
}
exit 0
