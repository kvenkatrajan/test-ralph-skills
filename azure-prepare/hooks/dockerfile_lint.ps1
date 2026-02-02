<#
.SYNOPSIS
    Validates Dockerfile best practices.

.DESCRIPTION
    This hook checks Dockerfiles for common issues and best practices.
    This is a non-blocking hook - failures are warnings.

.OUTPUTS
    JSON object with hook result
#>

param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"

$result = @{
    hook = "dockerfile_lint"
    status = "pass"
    blocking = $false  # Non-blocking hook
    error = $null
    fix_scope = @()
    details = @{
        dockerfiles_found = @()
        warnings = @()
        best_practices_violations = @()
    }
}

# Find all Dockerfiles
$dockerfiles = Get-ChildItem -Path $WorkspacePath -Filter "Dockerfile*" -Recurse -ErrorAction SilentlyContinue

if ($dockerfiles.Count -eq 0) {
    # No Dockerfiles is not a failure for this hook
    $result.details.dockerfiles_found = @()
    Write-Output ($result | ConvertTo-Json -Depth 10)
    exit 0
}

# Best practice checks
$bestPractices = @(
    @{
        name = "Use specific base image tag"
        pattern = "FROM\s+\w+:latest"
        message = "Avoid using ':latest' tag - use specific version tags for reproducible builds"
        severity = "warning"
    },
    @{
        name = "No root user"
        antiPattern = "USER\s+root"
        checkAbsence = $false
        message = "Running as root is a security risk - consider using a non-root user"
        severity = "warning"
    },
    @{
        name = "Use COPY instead of ADD"
        pattern = "ADD\s+[^h]"  # ADD not followed by http (URL)
        message = "Use COPY instead of ADD for local files - ADD has unexpected behaviors"
        severity = "info"
    },
    @{
        name = "Health check defined"
        checkPresence = "HEALTHCHECK"
        message = "Consider adding HEALTHCHECK instruction for container health monitoring"
        severity = "info"
    },
    @{
        name = "No secrets in ENV"
        pattern = "ENV\s+.*(PASSWORD|SECRET|KEY|TOKEN)\s*="
        message = "Avoid hardcoding secrets in ENV instructions"
        severity = "error"
    },
    @{
        name = "Multi-stage build"
        checkPresence = "FROM.*AS\s+\w+"
        message = "Consider using multi-stage builds to reduce final image size"
        severity = "info"
    },
    @{
        name = "npm ci requires lockfile"
        pattern = "RUN\s+npm\s+ci"
        requiresFile = "package-lock.json"
        message = "npm ci requires package-lock.json - use 'npm install' or generate lockfile first"
        severity = "error"
    },
    @{
        name = "npm install should omit dev dependencies"
        pattern = "RUN\s+npm\s+install(?!\s+--omit|\s+--production|\s+-g)"
        message = "Use 'npm install --omit=dev' in production to exclude dev dependencies"
        severity = "warning"
    },
    @{
        name = "Unpinned apt packages"
        pattern = "apt-get\s+install\s+(?!.*=\d).*-y"
        message = "Pin apt package versions for reproducible builds (e.g., package=1.2.3)"
        severity = "warning"
    },
    @{
        name = "Missing .dockerignore"
        checkDockerignore = $true
        message = "Add .dockerignore to exclude node_modules, .git, and other unnecessary files"
        severity = "warning"
    }
)

foreach ($dockerfile in $dockerfiles) {
    $relativePath = $dockerfile.FullName.Replace($WorkspacePath, "").TrimStart("\", "/")
    $result.details.dockerfiles_found += $relativePath
    
    $content = Get-Content $dockerfile.FullName -Raw -ErrorAction SilentlyContinue
    
    if ($content) {
        foreach ($check in $bestPractices) {
            $violation = $false
            
            if ($check.pattern) {
                if ($content -match $check.pattern) {
                    $violation = $true
                }
            }
            
            if ($check.checkPresence) {
                if ($content -notmatch $check.checkPresence) {
                    $violation = $true
                }
            }
            
            # Check if a required file exists alongside the Dockerfile
            if ($check.requiresFile) {
                $dockerDir = Split-Path $dockerfile.FullName -Parent
                $requiredFile = Join-Path $dockerDir $check.requiresFile
                if (($content -match $check.pattern) -and (-not (Test-Path $requiredFile))) {
                    $violation = $true
                } else {
                    $violation = $false  # File exists, no violation
                }
            }
            
            # Check for .dockerignore in same directory as Dockerfile
            if ($check.checkDockerignore) {
                $dockerDir = Split-Path $dockerfile.FullName -Parent
                $dockerignore = Join-Path $dockerDir ".dockerignore"
                if (-not (Test-Path $dockerignore)) {
                    $violation = $true
                }
            }
            
            if ($violation) {
                $result.details.best_practices_violations += @{
                    file = $relativePath
                    check = $check.name
                    message = $check.message
                    severity = $check.severity
                }
                
                if ($check.severity -eq "error") {
                    $result.fix_scope += $relativePath
                }
                
                if ($check.severity -eq "warning") {
                    $result.details.warnings += "$relativePath : $($check.message)"
                }
            }
        }
    }
}

# Only fail on errors, not warnings
$errors = $result.details.best_practices_violations | Where-Object { $_.severity -eq "error" }

if ($errors.Count -gt 0) {
    $result.status = "fail"
    $result.error = "Found $($errors.Count) Dockerfile best practice error(s)"
    $result.fix_scope = $result.fix_scope | Select-Object -Unique
}

Write-Output ($result | ConvertTo-Json -Depth 10)

if ($result.status -eq "fail") {
    exit 1
}
exit 0
