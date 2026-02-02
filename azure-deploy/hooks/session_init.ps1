<#
.SYNOPSIS
    Session start hook - initializes deploy manifest and validates prerequisites.

.DESCRIPTION
    Triggered by GitHub Copilot when a new agent session begins for deployment.
    Creates deploy manifest and checks prerequisites.
#>

$ErrorActionPreference = "Continue"

# Read input from stdin (Copilot hook format)
$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json

$cwd = $inputJson.cwd
$timestamp = $inputJson.timestamp
$source = $inputJson.source

# Create .azure directory if it doesn't exist
$azureDir = Join-Path $cwd ".azure"
if (-not (Test-Path $azureDir)) {
    New-Item -ItemType Directory -Path $azureDir -Force | Out-Null
}

# Initialize deploy manifest if it doesn't exist
$deployManifestPath = Join-Path $azureDir "deploy-manifest.md"
if (-not (Test-Path $deployManifestPath)) {
    $deployManifestContent = @"
# Deploy Manifest

Generated: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
Status: In Progress

---

## Deploy Status

| Attribute | Value |
|-----------|-------|
| Attempt | 1 |
| Last Deploy | - |
| Recipe | TBD |
| Exit Code | - |
| Status | In Progress |

---

## Prerequisites

| Prerequisite | Status |
|--------------|--------|
| Preparation Manifest | ⏳ Checking |
| Validation Status | ⏳ Checking |
| Azure Auth | ⏳ Checking |
| CLI Tools | ⏳ Checking |
| Environment | ⏳ Checking |

---

## Deployment History

| Attempt | Time | Command | Exit Code | Result |
|---------|------|---------|-----------|--------|
| - | - | - | - | - |

---

## Endpoints

| Service | URL | Health |
|---------|-----|--------|
| (pending deployment) | | |

---

## Hook Results

| Hook | Status | Last Run | Error |
|------|--------|----------|-------|
| auth_check | ⏳ | | |
| manifest_check | ⏳ | | |
| env_check | ⏳ | | |
| deploy_execute | ⏳ | | |
| health_check | ⏳ | | |

---

## Next Steps

1. Verify prerequisites
2. Configure environment
3. Execute deployment
4. Verify health
5. Update status
"@
    Set-Content -Path $deployManifestPath -Value $deployManifestContent
}

# Check prerequisites and update manifest
$prepManifestPath = Join-Path $azureDir "preparation-manifest.md"
$prereqStatus = @{
    preparation_manifest = (Test-Path $prepManifestPath)
    validation_status = $false
}

if ($prereqStatus.preparation_manifest) {
    $prepContent = Get-Content $prepManifestPath -Raw
    $prereqStatus.validation_status = $prepContent -match "Status:\s*Validated"
}

# Check CLI tools
$prereqStatus.azd_installed = $null -ne (Get-Command "azd" -ErrorAction SilentlyContinue)
$prereqStatus.az_installed = $null -ne (Get-Command "az" -ErrorAction SilentlyContinue)

# Log session start
$logPath = Join-Path $azureDir "session.log"
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Deploy session started (source: $source)" | Add-Content -Path $logPath
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Prerequisites - PrepManifest: $($prereqStatus.preparation_manifest), Validated: $($prereqStatus.validation_status), AZD: $($prereqStatus.azd_installed), AZ: $($prereqStatus.az_installed)" | Add-Content -Path $logPath

# Session start hook output is ignored by Copilot
exit 0
