#!/bin/bash
#
# Pre-deploy manifest check - blocks deployment if manifest not validated by azure-validate skill.
#
# Triggered by GitHub Copilot BEFORE any deployment tool is used.
# Checks if .azure/preparation-manifest.md exists with:
# - Status: Validated
# - Validated By: azure-validate
# - Validation Checksum (proves azure-validate was actually run)
# Returns permissionDecision: deny if not properly validated.
#

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.toolName // ""')
COMMAND=$(echo "$INPUT_JSON" | jq -r '.toolInput.command // ""')
CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')

# Only check for deployment-related commands
IS_DEPLOY_COMMAND=false
if [ "$TOOL_NAME" = "run_in_terminal" ] || [ "$TOOL_NAME" = "bash" ] || [ "$TOOL_NAME" = "powershell" ]; then
    if echo "$COMMAND" | grep -qE "(azd up|azd deploy|azd provision|az deployment|terraform apply|bicep deploy)"; then
        IS_DEPLOY_COMMAND=true
    fi
fi

# Skip check if not a deploy command
if [ "$IS_DEPLOY_COMMAND" = "false" ]; then
    exit 0
fi

AZURE_DIR="$CWD/.azure"
MANIFEST_PATH="$AZURE_DIR/preparation-manifest.md"
LOG_PATH="$AZURE_DIR/session.log"

# Check if manifest exists
if [ ! -f "$MANIFEST_PATH" ]; then
    echo '{"permissionDecision":"deny","permissionDecisionReason":"Preparation manifest not found at .azure/preparation-manifest.md. Run azure-prepare skill first."}'
    
    if [ -d "$AZURE_DIR" ]; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - Manifest not found" >> "$LOG_PATH"
    fi
    exit 0
fi

MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")

# Check 1: Status must be Validated
if ! echo "$MANIFEST_CONTENT" | grep -qE "Status\s*\|\s*Validated"; then
    CURRENT_STATUS=$(echo "$MANIFEST_CONTENT" | grep -oP "Status\s*\|\s*\K[^|]+" | head -1 | xargs || echo "Unknown")
    
    echo "{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Manifest status is '$CURRENT_STATUS', not 'Validated'. Run azure-validate skill first before deploying.\"}"
    
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - Manifest status is '$CURRENT_STATUS' (requires 'Validated')" >> "$LOG_PATH"
    exit 0
fi

# Check 2: Must have "Validated By: azure-validate" - proves the skill was invoked
if ! echo "$MANIFEST_CONTENT" | grep -qE "Validated By\s*\|\s*azure-validate"; then
    echo '{"permissionDecision":"deny","permissionDecisionReason":"Manifest missing '\''Validated By: azure-validate'\'' field. The azure-validate skill must be invoked to validate the deployment. Manual status changes are not accepted."}'
    
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - Missing 'Validated By: azure-validate' (skill was not invoked)" >> "$LOG_PATH"
    exit 0
fi

# Check 3: Must have a validation checksum
if ! echo "$MANIFEST_CONTENT" | grep -qE "Validation Checksum\s*\|\s*[a-f0-9]{8}"; then
    echo '{"permissionDecision":"deny","permissionDecisionReason":"Manifest missing validation checksum. The azure-validate skill must be properly invoked to generate a checksum. Re-run azure-validate."}'
    
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - Missing validation checksum" >> "$LOG_PATH"
    exit 0
fi

# All checks passed - allow the operation
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Manifest check passed (status: Validated, validated by: azure-validate, checksum: present)" >> "$LOG_PATH"
exit 0
