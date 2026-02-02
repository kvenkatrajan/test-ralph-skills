<#
.SYNOPSIS
    Validates Infrastructure as Code (Bicep/Terraform) syntax.

.DESCRIPTION
    This hook checks that IaC files in the infra/ directory compile/validate correctly.
    Supports both Bicep and Terraform.

.OUTPUTS
    JSON object with hook result
#>

param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"

$result = @{
    hook = "infra_lint"
    status = "pass"
    blocking = $true
    error = $null
    fix_scope = @()
    details = @{
        iac_type = $null
        files_checked = @()
        errors = @()
    }
}

$infraPath = Join-Path $WorkspacePath "infra"

# Check if infra directory exists
if (-not (Test-Path $infraPath)) {
    $result.status = "fail"
    $result.error = "Infrastructure directory not found at ./infra/"
    $result.fix_scope = @("infra/")
    Write-Output ($result | ConvertTo-Json -Depth 10)
    exit 1
}

# Detect IaC type
$bicepFiles = Get-ChildItem -Path $infraPath -Filter "*.bicep" -Recurse -ErrorAction SilentlyContinue
$tfFiles = Get-ChildItem -Path $infraPath -Filter "*.tf" -Recurse -ErrorAction SilentlyContinue

if ($bicepFiles.Count -gt 0) {
    $result.details.iac_type = "bicep"
    
    # Check if Bicep CLI is available
    $bicepAvailable = Get-Command "az" -ErrorAction SilentlyContinue
    
    foreach ($file in $bicepFiles) {
        $result.details.files_checked += $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
        
        if ($bicepAvailable) {
            # Run Bicep build to validate
            $buildOutput = az bicep build --file $file.FullName 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                $result.details.errors += @{
                    file = $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
                    message = $buildOutput -join "`n"
                }
                $result.fix_scope += $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
            }
        } else {
            # Basic syntax check without CLI
            $content = Get-Content $file.FullName -Raw
            
            # Check for common issues
            if ($content -match "param\s+\w+\s*$" -and $content -notmatch "param\s+\w+\s+\w+") {
                $result.details.errors += @{
                    file = $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
                    message = "Parameter missing type annotation"
                }
                $result.fix_scope += $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
            }
        }
    }
}
elseif ($tfFiles.Count -gt 0) {
    $result.details.iac_type = "terraform"
    
    # Check if Terraform CLI is available
    $tfAvailable = Get-Command "terraform" -ErrorAction SilentlyContinue
    
    if ($tfAvailable) {
        Push-Location $infraPath
        try {
            # Initialize and validate
            $initOutput = terraform init -backend=false 2>&1
            $validateOutput = terraform validate -json 2>&1 | ConvertFrom-Json
            
            if (-not $validateOutput.valid) {
                foreach ($diag in $validateOutput.diagnostics) {
                    $result.details.errors += @{
                        file = $diag.range.filename
                        message = $diag.detail
                        severity = $diag.severity
                    }
                    if ($diag.range.filename) {
                        $result.fix_scope += "infra/$($diag.range.filename)"
                    }
                }
            }
            
            foreach ($file in $tfFiles) {
                $result.details.files_checked += $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
            }
        }
        finally {
            Pop-Location
        }
    } else {
        # Basic file existence check
        foreach ($file in $tfFiles) {
            $result.details.files_checked += $file.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
        }
    }
}
else {
    $result.status = "fail"
    $result.error = "No Bicep (.bicep) or Terraform (.tf) files found in ./infra/"
    $result.fix_scope = @("infra/")
    Write-Output ($result | ConvertTo-Json -Depth 10)
    exit 1
}

# Set final status
if ($result.details.errors.Count -gt 0) {
    $result.status = "fail"
    $result.error = "Infrastructure validation failed with $($result.details.errors.Count) error(s)"
    $result.fix_scope = $result.fix_scope | Select-Object -Unique
}

Write-Output ($result | ConvertTo-Json -Depth 10)

if ($result.status -eq "fail") {
    exit 1
}
exit 0
