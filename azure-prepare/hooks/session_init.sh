#!/bin/bash
#
# session_init.sh
# Session start hook - initializes preparation manifest and workspace state.
# Triggered by GitHub Copilot when a new agent session begins.

set -e

# Read input from stdin (Copilot hook format)
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp')
SOURCE=$(echo "$INPUT" | jq -r '.source')

# Create .azure directory if it doesn't exist
AZURE_DIR="$CWD/.azure"
mkdir -p "$AZURE_DIR"

# Initialize manifest if it doesn't exist
MANIFEST_PATH="$AZURE_DIR/preparation-manifest.md"
if [ ! -f "$MANIFEST_PATH" ]; then
    cat > "$MANIFEST_PATH" << 'MANIFEST'
# Preparation Manifest

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Status: In Progress

---

## Loop Status

| Attribute | Value |
|-----------|-------|
| Current Iteration | 1 |
| Last Hook Run | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |
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
MANIFEST
fi

# Log session start
LOG_PATH="$AZURE_DIR/session.log"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Session started (source: $SOURCE)" >> "$LOG_PATH"

# Session start hook output is ignored by Copilot
exit 0
