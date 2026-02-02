#!/bin/bash
#
# Pre-deploy auth check - blocks deployment if not authenticated to Azure.
#
# Triggered by GitHub Copilot BEFORE any deployment tool is used.
# Checks if user is authenticated to Azure via azd or az CLI.
# Returns permissionDecision: deny if not authenticated.
#

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.toolName // ""')
COMMAND=$(echo "$INPUT_JSON" | jq -r '.toolInput.command // ""')
CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')

# Only check for deployment-related commands
IS_DEPLOY_COMMAND=false
if [ "$TOOL_NAME" = "run_in_terminal" ] || [ "$TOOL_NAME" = "bash" ]; then
    if echo "$COMMAND" | grep -qE "(azd up|azd deploy|azd provision|az deployment|terraform apply|bicep deploy)"; then
        IS_DEPLOY_COMMAND=true
    fi
fi

# Skip check if not a deploy command
if [ "$IS_DEPLOY_COMMAND" = "false" ]; then
    exit 0
fi

# Check Azure authentication
AUTHENTICATED=false
AUTH_METHOD=""

# Check azd auth status
if azd auth login --check-status >/dev/null 2>&1; then
    AUTHENTICATED=true
    AUTH_METHOD="azd"
fi

# Fallback to az CLI check
if [ "$AUTHENTICATED" = "false" ]; then
    if az account show --query "user.name" -o tsv >/dev/null 2>&1; then
        AUTHENTICATED=true
        AUTH_METHOD="az"
    fi
fi

if [ "$AUTHENTICATED" = "false" ]; then
    # Block the operation
    echo '{"permissionDecision":"deny","permissionDecisionReason":"Not authenticated to Azure. Run '\''azd auth login'\'' or '\''az login'\'' first before deploying."}'
    
    # Log to session log
    LOG_PATH="$CWD/.azure/session.log"
    if [ -d "$(dirname "$LOG_PATH")" ]; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): BLOCKED - Auth check failed for command: $COMMAND" >> "$LOG_PATH"
    fi
    
    exit 0
fi

# Authenticated - allow the operation
LOG_PATH="$CWD/.azure/session.log"
if [ -d "$(dirname "$LOG_PATH")" ]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Auth check passed ($AUTH_METHOD)" >> "$LOG_PATH"
fi

exit 0
