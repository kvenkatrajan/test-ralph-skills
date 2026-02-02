#!/bin/bash
#
# session_complete.sh
# Session end hook - final validation and manifest status update.
# Triggered by GitHub Copilot when the agent session ends.

set -e

# Read input from stdin (Copilot hook format)
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp')
REASON=$(echo "$INPUT" | jq -r '.reason')

AZURE_DIR="$CWD/.azure"
MANIFEST_PATH="$AZURE_DIR/preparation-manifest.md"
HOOK_RESULTS_PATH="$AZURE_DIR/hook-results.json"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize checks
MANIFEST_COMPLETE="false"
MANIFEST_MSG="Manifest not found"
INFRA_EXISTS="false"
INFRA_MSG="No infrastructure files found"
NO_SECRETS="true"
SECRETS_MSG="No hardcoded secrets"

# Check 1: Manifest completeness
if [ -f "$MANIFEST_PATH" ]; then
    CONTENT=$(cat "$MANIFEST_PATH")
    MISSING=""
    
    for section in "## Requirements" "## Components" "## Recipe" "## Architecture" "## Generated Files"; do
        if ! echo "$CONTENT" | grep -qF "$section"; then
            if [ -n "$MISSING" ]; then MISSING="$MISSING, "; fi
            MISSING="$MISSING$section"
        fi
    done
    
    if [ -z "$MISSING" ]; then
        MANIFEST_COMPLETE="true"
        MANIFEST_MSG="All required sections present"
    else
        MANIFEST_MSG="Missing:$MISSING"
    fi
fi

# Check 2: Infrastructure exists
INFRA_PATH="$CWD/infra"
if [ -d "$INFRA_PATH" ]; then
    INFRA_COUNT=$(find "$INFRA_PATH" -type f \( -name "*.bicep" -o -name "*.tf" \) 2>/dev/null | wc -l)
    if [ "$INFRA_COUNT" -gt 0 ]; then
        INFRA_EXISTS="true"
        INFRA_MSG="Found $INFRA_COUNT IaC files"
    fi
fi

# Check 3: No secrets
FILES_TO_SCAN=$(find "$CWD/infra" "$CWD" -maxdepth 1 -type f \( -name "*.bicep" -o -name "*.tf" -o -name "azure.yaml" \) 2>/dev/null || true)
for file in $FILES_TO_SCAN; do
    if grep -qE "AccountKey=[A-Za-z0-9+/=]{88}|-----BEGIN.*PRIVATE KEY-----|password[[:space:]]*[=:][[:space:]]*['\"][^'\"]{8,}['\"]" "$file" 2>/dev/null; then
        NO_SECRETS="false"
        SECRETS_MSG="Hardcoded secrets detected"
        break
    fi
done

# Determine if prepare-ready
PREPARE_READY="false"
if [ "$MANIFEST_COMPLETE" = "true" ] && [ "$INFRA_EXISTS" = "true" ] && [ "$NO_SECRETS" = "true" ]; then
    PREPARE_READY="true"
fi

# Write final results
cat > "$HOOK_RESULTS_PATH" << EOF
{
  "timestamp": "$NOW",
  "sessionEndReason": "$REASON",
  "finalChecks": [
    {"name": "manifest_complete", "passed": $MANIFEST_COMPLETE, "message": "$MANIFEST_MSG"},
    {"name": "infrastructure_files", "passed": $INFRA_EXISTS, "message": "$INFRA_MSG"},
    {"name": "no_secrets", "passed": $NO_SECRETS, "message": "$SECRETS_MSG"}
  ],
  "prepareReady": $PREPARE_READY
}
EOF

# Update manifest status
if [ -f "$MANIFEST_PATH" ]; then
    if [ "$PREPARE_READY" = "true" ]; then
        sed -i 's/Status:.*/Status: Prepare-Ready/' "$MANIFEST_PATH" 2>/dev/null || true
    else
        sed -i 's/Status:.*/Status: Incomplete/' "$MANIFEST_PATH" 2>/dev/null || true
    fi
fi

# Log session end
LOG_PATH="$AZURE_DIR/session.log"
STATUS="INCOMPLETE"
if [ "$PREPARE_READY" = "true" ]; then STATUS="READY"; fi
echo "$NOW: Session ended ($REASON) - Status: $STATUS" >> "$LOG_PATH"

# Session end hook output is ignored by Copilot
exit 0
