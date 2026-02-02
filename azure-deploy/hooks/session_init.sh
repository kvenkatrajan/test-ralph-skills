#!/bin/bash
#
# Session start hook - initializes deploy manifest and validates prerequisites.
#
# Triggered by GitHub Copilot when a new agent session begins for deployment.
# Creates deploy manifest and checks prerequisites.
#

set -e

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')
TIMESTAMP=$(echo "$INPUT_JSON" | jq -r '.timestamp // ""')
SOURCE=$(echo "$INPUT_JSON" | jq -r '.source // ""')

# Create .azure directory if it doesn't exist
AZURE_DIR="$CWD/.azure"
mkdir -p "$AZURE_DIR"

# Initialize deploy manifest if it doesn't exist
DEPLOY_MANIFEST_PATH="$AZURE_DIR/deploy-manifest.md"
if [ ! -f "$DEPLOY_MANIFEST_PATH" ]; then
    cat > "$DEPLOY_MANIFEST_PATH" << 'EOF'
# Deploy Manifest

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
EOF
fi

# Check prerequisites
PREP_MANIFEST_PATH="$AZURE_DIR/preparation-manifest.md"
PREP_MANIFEST_EXISTS=false
VALIDATION_STATUS=false

if [ -f "$PREP_MANIFEST_PATH" ]; then
    PREP_MANIFEST_EXISTS=true
    if grep -q "Status:.*Validated" "$PREP_MANIFEST_PATH"; then
        VALIDATION_STATUS=true
    fi
fi

# Check CLI tools
AZD_INSTALLED=$(command -v azd >/dev/null 2>&1 && echo "true" || echo "false")
AZ_INSTALLED=$(command -v az >/dev/null 2>&1 && echo "true" || echo "false")

# Log session start
LOG_PATH="$AZURE_DIR/session.log"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Deploy session started (source: $SOURCE)" >> "$LOG_PATH"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Prerequisites - PrepManifest: $PREP_MANIFEST_EXISTS, Validated: $VALIDATION_STATUS, AZD: $AZD_INSTALLED, AZ: $AZ_INSTALLED" >> "$LOG_PATH"

# Session start hook output is ignored by Copilot
exit 0
