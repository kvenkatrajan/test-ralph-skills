<#
.SYNOPSIS
    Validates the Azure preparation manifest for completeness.

.DESCRIPTION
    This hook checks that .azure/preparation-manifest.md exists and contains
    all required sections for Azure deployment preparation.

.OUTPUTS
    JSON object with hook result
#>

param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$result = @{
    hook = "manifest_check"
    status = "pass"
    blocking = $true
    error = $null
    fix_scope = @()
    details = @{
        sections_found = @()
        sections_missing = @()
    }
}

$manifestPath = Join-Path $WorkspacePath ".azure" "preparation-manifest.md"

# Check if manifest exists
if (-not (Test-Path $manifestPath)) {
    $result.status = "fail"
    $result.error = "Manifest file not found at .azure/preparation-manifest.md"
    $result.fix_scope = @(".azure/preparation-manifest.md")
    Write-Output ($result | ConvertTo-Json -Depth 10)
    exit 1
}

# Read manifest content
$content = Get-Content $manifestPath -Raw

# Required sections
$requiredSections = @(
    @{ name = "Requirements"; pattern = "## Requirements" },
    @{ name = "Components"; pattern = "## Components" },
    @{ name = "Recipe"; pattern = "## Recipe" },
    @{ name = "Architecture"; pattern = "## Architecture" },
    @{ name = "Generated Files"; pattern = "## Generated Files" }
)

# Check each required section
foreach ($section in $requiredSections) {
    if ($content -match [regex]::Escape($section.pattern)) {
        $result.details.sections_found += $section.name
    } else {
        $result.details.sections_missing += $section.name
    }
}

# Check for required fields in Requirements section
$requiredFields = @("Classification", "Scale", "Budget", "Region")
$missingFields = @()

foreach ($field in $requiredFields) {
    if ($content -notmatch $field) {
        $missingFields += $field
    }
}

# Determine pass/fail
if ($result.details.sections_missing.Count -gt 0) {
    $result.status = "fail"
    $result.error = "Missing required sections: $($result.details.sections_missing -join ', ')"
    $result.fix_scope = @(".azure/preparation-manifest.md")
}
elseif ($missingFields.Count -gt 0) {
    $result.status = "fail"
    $result.error = "Missing required fields in Requirements: $($missingFields -join ', ')"
    $result.fix_scope = @(".azure/preparation-manifest.md")
    $result.details.missing_fields = $missingFields
}

Write-Output ($result | ConvertTo-Json -Depth 10)

if ($result.status -eq "fail") {
    exit 1
}
exit 0
