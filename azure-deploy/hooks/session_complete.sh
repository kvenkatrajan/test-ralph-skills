#!/bin/bash
#
# Session end hook - final verification and deploy manifest status update.
#
# Triggered by GitHub Copilot when the agent session ends.
# Runs final verification and updates deploy manifest status.
#

# Read input from stdin (Copilot hook format)
INPUT_JSON=$(cat)

CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // "."')
TIMESTAMP=$(echo "$INPUT_JSON" | jq -r '.timestamp // ""')
REASON=$(echo "$INPUT_JSON" | jq -r '.reason // ""')

AZURE_DIR="$CWD/.azure"
DEPLOY_MANIFEST_PATH="$AZURE_DIR/deploy-manifest.md"
DEPLOY_RESULTS_PATH="$AZURE_DIR/deploy-results.json"
LOG_PATH="$AZURE_DIR/session.log"

CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize checks
CHECKS="[]"

# Check 1: Deploy manifest exists
MANIFEST_EXISTS=false
if [ -f "$DEPLOY_MANIFEST_PATH" ]; then
    MANIFEST_EXISTS=true
fi
CHECKS=$(echo "$CHECKS" | jq --arg passed "$MANIFEST_EXISTS" --arg msg "$([ "$MANIFEST_EXISTS" = "true" ] && echo "Deploy manifest found" || echo "Deploy manifest not found")" '. + [{name: "deploy_manifest_exists", passed: ($passed == "true"), message: $msg}]')

# Check 2: Deployment was attempted
DEPLOYMENT_ATTEMPTED=false
LAST_EXIT_CODE=-1
if [ -f "$DEPLOY_RESULTS_PATH" ]; then
    COMMAND=$(jq -r '.command // ""' "$DEPLOY_RESULTS_PATH")
    if [ -n "$COMMAND" ]; then
        DEPLOYMENT_ATTEMPTED=true
        LAST_EXIT_CODE=$(jq -r '.exitCode // -1' "$DEPLOY_RESULTS_PATH")
    fi
fi
CHECKS=$(echo "$CHECKS" | jq --arg passed "$DEPLOYMENT_ATTEMPTED" --arg code "$LAST_EXIT_CODE" --arg msg "$([ "$DEPLOYMENT_ATTEMPTED" = "true" ] && echo "Deployment was executed (exit code: $LAST_EXIT_CODE)" || echo "No deployment was attempted")" '. + [{name: "deployment_attempted", passed: ($passed == "true"), message: $msg}]')

# Check 3: Deployment succeeded
DEPLOY_SUCCEEDED=false
if [ "$DEPLOYMENT_ATTEMPTED" = "true" ] && [ "$LAST_EXIT_CODE" = "0" ]; then
    DEPLOY_SUCCEEDED=true
fi
CHECKS=$(echo "$CHECKS" | jq --arg passed "$DEPLOY_SUCCEEDED" --arg msg "$([ "$DEPLOY_SUCCEEDED" = "true" ] && echo "Deployment completed successfully" || echo "Deployment did not succeed")" '. + [{name: "deployment_succeeded", passed: ($passed == "true"), message: $msg}]')

# Check 4: Verification passed
VERIFICATION_PASSED=false
if [ -f "$DEPLOY_RESULTS_PATH" ]; then
    VERIFICATION_ALL_PASSED=$(jq -r '.verification.allPassed // .allPassed // false' "$DEPLOY_RESULTS_PATH")
    if [ "$VERIFICATION_ALL_PASSED" = "true" ]; then
        VERIFICATION_PASSED=true
    fi
fi
CHECKS=$(echo "$CHECKS" | jq --arg passed "$VERIFICATION_PASSED" --arg msg "$([ "$VERIFICATION_PASSED" = "true" ] && echo "All verification checks passed" || echo "Verification incomplete or failed")" '. + [{name: "verification_passed", passed: ($passed == "true"), message: $msg}]')

# Check 5: Endpoints healthy
ENDPOINTS_HEALTHY=true
HEALTHY_COUNT=0
TOTAL_COUNT=0
if [ -f "$DEPLOY_RESULTS_PATH" ]; then
    TOTAL_COUNT=$(jq -r '.verification.endpoints | length // 0' "$DEPLOY_RESULTS_PATH")
    HEALTHY_COUNT=$(jq -r '[.verification.endpoints[] | select(.health == "healthy")] | length // 0' "$DEPLOY_RESULTS_PATH")
    if [ "$TOTAL_COUNT" -gt 0 ] && [ "$HEALTHY_COUNT" -ne "$TOTAL_COUNT" ]; then
        ENDPOINTS_HEALTHY=false
    fi
fi
ENDPOINTS_MSG="No endpoints to verify"
if [ "$TOTAL_COUNT" -gt 0 ]; then
    ENDPOINTS_MSG="$HEALTHY_COUNT of $TOTAL_COUNT endpoints healthy"
fi
CHECKS=$(echo "$CHECKS" | jq --arg passed "$ENDPOINTS_HEALTHY" --arg msg "$ENDPOINTS_MSG" '. + [{name: "endpoints_healthy", passed: ($passed == "true"), message: $msg}]')

# Determine if deployment is complete
FAILED_COUNT=$(echo "$CHECKS" | jq '[.[] | select(.passed == false)] | length')
ALL_PASSED=false
if [ "$FAILED_COUNT" = "0" ]; then
    ALL_PASSED=true
fi

# Update deploy manifest status
if [ -f "$DEPLOY_MANIFEST_PATH" ]; then
    NEW_STATUS="Failed"
    if [ "$ALL_PASSED" = "true" ]; then
        NEW_STATUS="Deployed"
    elif [ "$DEPLOY_SUCCEEDED" = "true" ]; then
        NEW_STATUS="Deployed (Unverified)"
    fi
    
    sed -i "s/Status |[^|]*|/Status | $NEW_STATUS |/" "$DEPLOY_MANIFEST_PATH"
fi

# Write final results
cat > "$DEPLOY_RESULTS_PATH" << EOF
{
  "timestamp": "$CURRENT_TIMESTAMP",
  "sessionEndReason": "$REASON",
  "finalChecks": $CHECKS,
  "deployComplete": $ALL_PASSED
}
EOF

# Log session end
STATUS="INCOMPLETE"
if [ "$ALL_PASSED" = "true" ]; then
    STATUS="COMPLETE"
elif [ "$DEPLOY_SUCCEEDED" = "true" ]; then
    STATUS="DEPLOYED (UNVERIFIED)"
fi
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Deploy session ended ($REASON) - Status: $STATUS" >> "$LOG_PATH"

# Session end hook output is ignored by Copilot
exit 0
