<#
.SYNOPSIS
    Session start hook - initializes preparation manifest and workspace state.

.DESCRIPTION
    Triggered by GitHub Copilot when a new agent session begins.
    Creates initial manifest structure if it doesn't exist.
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

# Initialize manifest if it doesn't exist
$manifestPath = Join-Path $azureDir "preparation-manifest.md"
if (-not (Test-Path $manifestPath)) {
    $manifestContent = @"
# Preparation Manifest

Generated: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
Status: In Progress

---

## Loop Status

| Attribute | Value |
|-----------|-------|
| Current Iteration | 1 |
| Last Hook Run | $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") |
| Blocking Failures | 0 |
| Status | In Progress |

---

## Requirements

| Attribute | Value |
|-----------|-------|
| Classification | TBD |
| Scale | TBD |
| Budget | TBD |
| Primary Region | TBD |

---

## Components

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| (pending scan) | | | |

---

## Recipe

**Selected:** TBD

**Rationale:** (pending)

---

## Architecture

**Stack:** TBD

### Service Mapping

| Component | Azure Service | SKU |
|-----------|---------------|-----|
| (pending) | | |

---

## Generated Files

| File | Status |
|------|--------|
| (none yet) | |

---

## Hook Results

| Hook | Status | Last Run | Error |
|------|--------|----------|-------|
| manifest_check | ⏳ | | |
| infra_lint | ⏳ | | |
| secrets_scan | ⏳ | | |
| dockerfile_lint | ⏳ | | |
| azure_yaml_check | ⏳ | | |

---

## Next Steps

1. Gather requirements
2. Scan codebase
3. Select recipe
4. Generate artifacts
5. Run validation hooks
"@
    Set-Content -Path $manifestPath -Value $manifestContent
}

# Log session start
$logPath = Join-Path $azureDir "session.log"
"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'): Session started (source: $source)" | Add-Content -Path $logPath

# Session start hook output is ignored by Copilot
exit 0
