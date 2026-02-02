#!/bin/bash
#
# Post-deploy verify hook - verifies deployment succeeded and runs health checks.
#
# Triggered by GitHub Copilot AFTER deployment commands complete.
# Verifies resources deployed and endpoints are healthy.
# Updates deploy-results.json with verification status.
#

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.toolName // ""')
COMMAND=$(echo "$INPUT_JSON" | jq -r '.toolInput.command // ""')
CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')
EXIT_CODE=$(echo "$INPUT_JSON" | jq -r '.toolResult.exitCode // (if .toolResult.resultType == "success" then 0 else 1 end)')

# Only verify after deployment-related commands
IS_DEPLOY_COMMAND=false
if [ "$TOOL_NAME" = "run_in_terminal" ] || [ "$TOOL_NAME" = "bash" ]; then
    if echo "$COMMAND" | grep -qE "(azd up|azd deploy|azd provision)"; then
        IS_DEPLOY_COMMAND=true
    fi
fi

# Skip if not a deploy command
if [ "$IS_DEPLOY_COMMAND" = "false" ]; then
    exit 0
fi

# Skip if command failed
if [ "$EXIT_CODE" != "0" ]; then
    exit 0
fi

AZURE_DIR="$CWD/.azure"
DEPLOY_RESULTS_PATH="$AZURE_DIR/deploy-results.json"
DEPLOY_MANIFEST_PATH="$AZURE_DIR/deploy-manifest.md"
LOG_PATH="$AZURE_DIR/session.log"

# Ensure .azure directory exists
if [ ! -d "$AZURE_DIR" ]; then
    exit 0
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Check 1: Get deployed resources via azd show
RESOURCES_PASSED=false
RESOURCES_MESSAGE=""
ENDPOINTS="[]"

SHOW_OUTPUT=$(azd show --output json 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$SHOW_OUTPUT" ]; then
    SERVICE_COUNT=$(echo "$SHOW_OUTPUT" | jq '.services | length // 0')
    if [ "$SERVICE_COUNT" -gt 0 ]; then
        RESOURCES_PASSED=true
        RESOURCES_MESSAGE="Found $SERVICE_COUNT deployed services"
        
        # Extract endpoints
        ENDPOINTS=$(echo "$SHOW_OUTPUT" | jq '[.services | to_entries[] | select(.value.endpoint) | {name: .key, url: .value.endpoint, health: "pending"}]')
    else
        RESOURCES_MESSAGE="No services found in azd show output"
    fi
else
    RESOURCES_MESSAGE="Failed to get resource info from azd show"
fi

# Check 2: Health check endpoints
HEALTH_PASSED=false
HEALTH_MESSAGE=""
HEALTHY_COUNT=0
TOTAL_ENDPOINTS=$(echo "$ENDPOINTS" | jq 'length')

if [ "$TOTAL_ENDPOINTS" -eq 0 ]; then
    HEALTH_PASSED=true
    HEALTH_MESSAGE="No endpoints to check (infrastructure only?)"
else
    # Check each endpoint
    UPDATED_ENDPOINTS="[]"
    for i in $(seq 0 $((TOTAL_ENDPOINTS - 1))); do
        ENDPOINT=$(echo "$ENDPOINTS" | jq -r ".[$i]")
        URL=$(echo "$ENDPOINT" | jq -r '.url')
        NAME=$(echo "$ENDPOINT" | jq -r '.name')
        
        # Try to reach the endpoint
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$URL" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
            UPDATED_ENDPOINTS=$(echo "$UPDATED_ENDPOINTS" | jq --arg name "$NAME" --arg url "$URL" '. + [{name: $name, url: $url, health: "healthy"}]')
            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
        else
            # Try /health endpoint
            HEALTH_URL="${URL%/}/health"
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$HEALTH_URL" 2>/dev/null || echo "000")
            
            if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
                UPDATED_ENDPOINTS=$(echo "$UPDATED_ENDPOINTS" | jq --arg name "$NAME" --arg url "$URL" '. + [{name: $name, url: $url, health: "healthy"}]')
                HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
            else
                UPDATED_ENDPOINTS=$(echo "$UPDATED_ENDPOINTS" | jq --arg name "$NAME" --arg url "$URL" --arg code "$HTTP_CODE" '. + [{name: $name, url: $url, health: ("unhealthy (HTTP " + $code + ")")}]')
            fi
        fi
    done
    ENDPOINTS="$UPDATED_ENDPOINTS"
    
    if [ "$HEALTHY_COUNT" -eq "$TOTAL_ENDPOINTS" ]; then
        HEALTH_PASSED=true
        HEALTH_MESSAGE="All $TOTAL_ENDPOINTS endpoints healthy"
    else
        HEALTH_MESSAGE="$HEALTHY_COUNT of $TOTAL_ENDPOINTS endpoints healthy"
    fi
fi

# Calculate overall status
ALL_PASSED=false
if [ "$RESOURCES_PASSED" = "true" ] && [ "$HEALTH_PASSED" = "true" ]; then
    ALL_PASSED=true
fi

# Build verification results
VERIFICATION_JSON=$(cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "checks": [
    {"name": "resources_deployed", "passed": $RESOURCES_PASSED, "message": "$RESOURCES_MESSAGE"},
    {"name": "health_check", "passed": $HEALTH_PASSED, "message": "$HEALTH_MESSAGE"}
  ],
  "endpoints": $ENDPOINTS,
  "allPassed": $ALL_PASSED
}
EOF
)

# Merge with existing results if present
if [ -f "$DEPLOY_RESULTS_PATH" ]; then
    EXISTING=$(cat "$DEPLOY_RESULTS_PATH")
    echo "$EXISTING" | jq --argjson verification "$VERIFICATION_JSON" '. + {verification: $verification, allPassed: $verification.allPassed}' > "$DEPLOY_RESULTS_PATH"
else
    echo "$VERIFICATION_JSON" > "$DEPLOY_RESULTS_PATH"
fi

# Update manifest with status and endpoints
if [ -f "$DEPLOY_MANIFEST_PATH" ]; then
    if [ "$ALL_PASSED" = "true" ]; then
        sed -i 's/Status | In Progress/Status | Deployed/' "$DEPLOY_MANIFEST_PATH"
    fi
fi

# Log verification
STATUS="FAILED"
if [ "$ALL_PASSED" = "true" ]; then
    STATUS="PASSED"
fi
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Verification $STATUS - $HEALTHY_COUNT/$TOTAL_ENDPOINTS endpoints healthy" >> "$LOG_PATH"

# Post-tool hook output is ignored by Copilot
exit 0
