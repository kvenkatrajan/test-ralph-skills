#!/bin/bash
#
# Runs all deploy hooks and aggregates results.
#
# Helper script to execute all deployment hooks in sequence
# and produce a consolidated results report.
#
# Usage: ./run_hooks.sh [workspace_path] [hook_type]
#   hook_type: pre-deploy, post-deploy, or all (default)
#

WORKSPACE_PATH="${1:-.}"
HOOK_TYPE="${2:-all}"

HOOKS_DIR="$(dirname "$0")"
AZURE_DIR="$WORKSPACE_PATH/.azure"
RESULTS_PATH="$AZURE_DIR/hook-results.json"

# Ensure .azure directory exists
mkdir -p "$AZURE_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize results
HOOKS_RESULTS="[]"
ALL_PASSED=true

# Define hooks by type
PRE_DEPLOY_HOOKS="auth_check:pre_deploy_auth_check.sh manifest_check:pre_deploy_manifest_check.sh env_check:pre_deploy_env_check.sh"
POST_DEPLOY_HOOKS="deploy_capture:post_deploy_capture.sh deploy_verify:post_deploy_verify.sh"

# Select hooks to run
HOOKS_TO_RUN=""
case "$HOOK_TYPE" in
    "pre-deploy")
        HOOKS_TO_RUN="$PRE_DEPLOY_HOOKS"
        ;;
    "post-deploy")
        HOOKS_TO_RUN="$POST_DEPLOY_HOOKS"
        ;;
    "all")
        HOOKS_TO_RUN="$PRE_DEPLOY_HOOKS $POST_DEPLOY_HOOKS"
        ;;
esac

# Run each hook
for HOOK_DEF in $HOOKS_TO_RUN; do
    HOOK_NAME="${HOOK_DEF%%:*}"
    HOOK_SCRIPT="${HOOK_DEF##*:}"
    HOOK_PATH="$HOOKS_DIR/$HOOK_SCRIPT"
    
    if [ ! -f "$HOOK_PATH" ]; then
        HOOKS_RESULTS=$(echo "$HOOKS_RESULTS" | jq --arg name "$HOOK_NAME" --arg msg "Hook script not found: $HOOK_SCRIPT" '. + [{name: $name, status: "skip", message: $msg}]')
        continue
    fi
    
    echo "Running hook: $HOOK_NAME..."
    
    # Make executable
    chmod +x "$HOOK_PATH"
    
    # Run hook
    HOOK_OUTPUT=$("$HOOK_PATH" "$WORKSPACE_PATH" 2>&1)
    HOOK_EXIT_CODE=$?
    
    STATUS="pass"
    if [ $HOOK_EXIT_CODE -ne 0 ]; then
        STATUS="fail"
        ALL_PASSED=false
        echo "  ❌ FAILED"
    else
        echo "  ✅ PASSED"
    fi
    
    # Try to capture result as JSON or plain text
    HOOKS_RESULTS=$(echo "$HOOKS_RESULTS" | jq --arg name "$HOOK_NAME" --arg status "$STATUS" --arg code "$HOOK_EXIT_CODE" '. + [{name: $name, status: $status, exitCode: ($code | tonumber)}]')
done

# Write results
cat > "$RESULTS_PATH" << EOF
{
  "timestamp": "$TIMESTAMP",
  "hookType": "$HOOK_TYPE",
  "hooks": $HOOKS_RESULTS,
  "allPassed": $ALL_PASSED
}
EOF

# Summary
echo ""
echo "========================================"
echo "Hook Results Summary"
echo "========================================"

PASSED_COUNT=$(echo "$HOOKS_RESULTS" | jq '[.[] | select(.status == "pass")] | length')
FAILED_COUNT=$(echo "$HOOKS_RESULTS" | jq '[.[] | select(.status == "fail")] | length')
TOTAL_COUNT=$(echo "$HOOKS_RESULTS" | jq 'length')

echo "Total: $TOTAL_COUNT | Passed: $PASSED_COUNT | Failed: $FAILED_COUNT"

if [ "$ALL_PASSED" = "true" ]; then
    echo "✅ All hooks passed!"
    exit 0
else
    echo "❌ Some hooks failed. Check $RESULTS_PATH for details."
    exit 1
fi
