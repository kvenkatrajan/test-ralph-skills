#!/bin/bash
#
# Pre-deploy environment check - blocks deployment if environment not configured.
#
# Triggered by GitHub Copilot BEFORE any deployment tool is used.
# Checks if azd environment is selected and configured.
# Returns permissionDecision: deny if environment not ready.
#

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.toolName // ""')
COMMAND=$(echo "$INPUT_JSON" | jq -r '.toolInput.command // ""')
CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')

# Only check for deployment-related commands
IS_DEPLOY_COMMAND=false
if [ "$TOOL_NAME" = "run_in_terminal" ] || [ "$TOOL_NAME" = "bash" ]; then
    if echo "$COMMAND" | grep -qE "(azd up|azd deploy|azd provision)"; then
        IS_DEPLOY_COMMAND=true
    fi
fi

# Skip check if not a deploy command
if [ "$IS_DEPLOY_COMMAND" = "false" ]; then
    exit 0
fi

AZURE_DIR="$CWD/.azure"
LOG_PATH="$AZURE_DIR/session.log"

# Check if azure.yaml exists (required for azd)
AZURE_YAML_PATH="$CWD/azure.yaml"
if [ ! -f "$AZURE_YAML_PATH" ]; then
    echo '{"permissionDecision":"deny","permissionDecisionReason":"azure.yaml not found. The application must be prepared for Azure deployment first. Run azure-prepare skill."}'
    
    if [ -d "$AZURE_DIR" ]; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - azure.yaml not found" >> "$LOG_PATH"
    fi
    exit 0
fi

# Check if azd environment exists
ENV_CHECK_PASSED=false
ENV_NAME=""

# Get current environment
ENV_OUTPUT=$(azd env list --output json 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$ENV_OUTPUT" ]; then
    ENV_COUNT=$(echo "$ENV_OUTPUT" | jq 'length')
    if [ "$ENV_COUNT" -gt 0 ]; then
        ENV_CHECK_PASSED=true
        ENV_NAME=$(echo "$ENV_OUTPUT" | jq -r '.[0].Name // "default"')
    fi
else
    # azd env check failed - might be first deployment
    # Allow to proceed, azd up will create environment
    ENV_CHECK_PASSED=true
    ENV_NAME="(will be created)"
fi

if [ "$ENV_CHECK_PASSED" = "false" ]; then
    echo '{"permissionDecision":"deny","permissionDecisionReason":"No azd environment configured. Run '\''azd env new <name>'\'' to create one first."}'
    
    if [ -d "$AZURE_DIR" ]; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - No azd environment configured" >> "$LOG_PATH"
    fi
    exit 0
fi

# Environment check passed
if [ -d "$AZURE_DIR" ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Environment check passed (env: $ENV_NAME)" >> "$LOG_PATH"
fi
exit 0
