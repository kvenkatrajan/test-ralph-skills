#!/bin/bash
#
# Post-deploy capture hook - captures deployment output and detects errors.
#
# Triggered by GitHub Copilot AFTER any deployment tool completes.
# Captures output to log file and updates deploy manifest.
#

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.toolName // ""')
COMMAND=$(echo "$INPUT_JSON" | jq -r '.toolInput.command // ""')
CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')
OUTPUT=$(echo "$INPUT_JSON" | jq -r '.toolResult.output // .toolResult.stdout // ""')
EXIT_CODE=$(echo "$INPUT_JSON" | jq -r '.toolResult.exitCode // (if .toolResult.resultType == "success" then 0 else 1 end)')

# Only capture for deployment-related commands
IS_DEPLOY_COMMAND=false
if [ "$TOOL_NAME" = "run_in_terminal" ] || [ "$TOOL_NAME" = "bash" ]; then
    if echo "$COMMAND" | grep -qE "(azd up|azd deploy|azd provision|az deployment|terraform apply)"; then
        IS_DEPLOY_COMMAND=true
    fi
fi

# Skip if not a deploy command
if [ "$IS_DEPLOY_COMMAND" = "false" ]; then
    exit 0
fi

AZURE_DIR="$CWD/.azure"
DEPLOY_OUTPUT_PATH="$AZURE_DIR/deploy-output.log"
DEPLOY_RESULTS_PATH="$AZURE_DIR/deploy-results.json"
DEPLOY_MANIFEST_PATH="$AZURE_DIR/deploy-manifest.md"
LOG_PATH="$AZURE_DIR/session.log"

# Ensure .azure directory exists
mkdir -p "$AZURE_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Capture output to log file
cat >> "$DEPLOY_OUTPUT_PATH" << EOF
================================================================================
Deployment Capture: $TIMESTAMP
Command: $COMMAND
Exit Code: $EXIT_CODE
================================================================================
$OUTPUT
================================================================================

EOF

# Detect common errors in output
ERRORS="[]"
if echo "$OUTPUT" | grep -qi "not authenticated"; then
    ERRORS=$(echo "$ERRORS" | jq '. + [{"pattern":"not authenticated","suggestion":"Authentication required - run azd auth login"}]')
fi
if echo "$OUTPUT" | grep -qi "quota exceeded"; then
    ERRORS=$(echo "$ERRORS" | jq '. + [{"pattern":"quota exceeded","suggestion":"Resource quota exceeded - request increase or change region"}]')
fi
if echo "$OUTPUT" | grep -qi "already exists"; then
    ERRORS=$(echo "$ERRORS" | jq '. + [{"pattern":"already exists","suggestion":"Resource name conflict - use a different name"}]')
fi
if echo "$OUTPUT" | grep -qi "permission denied"; then
    ERRORS=$(echo "$ERRORS" | jq '. + [{"pattern":"permission denied","suggestion":"Insufficient permissions - check RBAC"}]')
fi

# Read current attempt number from manifest
CURRENT_ATTEMPT=1
if [ -f "$DEPLOY_MANIFEST_PATH" ]; then
    CURRENT_ATTEMPT=$(grep -oP "Attempt\s*\|\s*\K\d+" "$DEPLOY_MANIFEST_PATH" | head -1 || echo "1")
fi

# Determine success
SUCCESS=false
if [ "$EXIT_CODE" = "0" ]; then
    SUCCESS=true
fi

# Build and write results
cat > "$DEPLOY_RESULTS_PATH" << EOF
{
  "timestamp": "$TIMESTAMP",
  "attempt": $CURRENT_ATTEMPT,
  "command": "$COMMAND",
  "exitCode": $EXIT_CODE,
  "success": $SUCCESS,
  "errors": $ERRORS,
  "outputLength": ${#OUTPUT}
}
EOF

# Update manifest with deployment attempt
if [ -f "$DEPLOY_MANIFEST_PATH" ]; then
    sed -i "s/Last Deploy |[^|]*|/Last Deploy | $TIMESTAMP |/" "$DEPLOY_MANIFEST_PATH"
    sed -i "s/Exit Code |[^|]*|/Exit Code | $EXIT_CODE |/" "$DEPLOY_MANIFEST_PATH"
fi

# Log capture
RESULT_TEXT="SUCCESS"
ERROR_COUNT=$(echo "$ERRORS" | jq 'length')
if [ "$EXIT_CODE" != "0" ]; then
    RESULT_TEXT="FAILED (errors: $ERROR_COUNT)"
fi
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Deploy capture - $COMMAND - Exit: $EXIT_CODE - $RESULT_TEXT" >> "$LOG_PATH"

# Post-tool hook output is ignored by Copilot
exit 0
