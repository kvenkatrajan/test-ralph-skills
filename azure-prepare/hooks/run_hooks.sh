#!/bin/bash
#
# run_hooks.sh
# Hook dispatcher for Ralph Wiggum loop.
# Runs all required hooks and aggregates results.
#
# Usage: ./run_hooks.sh [hook_name] [workspace_path]

set -e

HOOK_NAME="${1:-}"
WORKSPACE_PATH="${2:-$(pwd)}"
HOOKS_DIR="$(dirname "$0")"

# Define all hooks (name:blocking)
ALL_HOOKS=(
    "manifest_check:true"
    "infra_lint:true"
    "secrets_scan:true"
    "dockerfile_lint:false"
    "azure_yaml_check:true"
)

# Initialize aggregated results
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOTAL=0
PASSED=0
FAILED=0
BLOCKING_FAILED=0

HOOKS_RUN="[]"
BLOCKING_FAILURES="[]"
NON_BLOCKING_FAILURES="[]"

# Filter hooks if specific one requested
if [ -n "$HOOK_NAME" ]; then
    HOOKS_TO_RUN=()
    for hook in "${ALL_HOOKS[@]}"; do
        name="${hook%%:*}"
        if [ "$name" = "$HOOK_NAME" ]; then
            HOOKS_TO_RUN+=("$hook")
        fi
    done
else
    HOOKS_TO_RUN=("${ALL_HOOKS[@]}")
fi

HOOKS_RUN_ARRAY=()
BLOCKING_FAILURES_ARRAY=()
NON_BLOCKING_FAILURES_ARRAY=()

for hook_def in "${HOOKS_TO_RUN[@]}"; do
    HOOK_NAME="${hook_def%%:*}"
    IS_BLOCKING="${hook_def##*:}"
    HOOK_SCRIPT="$HOOKS_DIR/${HOOK_NAME}.sh"
    
    if [ -f "$HOOK_SCRIPT" ]; then
        ((TOTAL++)) || true
        
        # Run hook and capture output
        set +e
        HOOK_OUTPUT=$("$HOOK_SCRIPT" "$WORKSPACE_PATH" 2>&1)
        HOOK_EXIT=$?
        set -e
        
        HOOKS_RUN_ARRAY+=("$HOOK_OUTPUT")
        
        # Parse status from output
        HOOK_STATUS=$(echo "$HOOK_OUTPUT" | jq -r '.status // "fail"')
        
        if [ "$HOOK_STATUS" = "pass" ]; then
            ((PASSED++)) || true
        else
            ((FAILED++)) || true
            
            HOOK_ERROR=$(echo "$HOOK_OUTPUT" | jq -r '.error // "Unknown error"')
            HOOK_FIX_SCOPE=$(echo "$HOOK_OUTPUT" | jq -c '.fix_scope // []')
            
            FAILURE_OBJ="{\"hook\": \"$HOOK_NAME\", \"error\": \"$HOOK_ERROR\", \"fix_scope\": $HOOK_FIX_SCOPE}"
            
            if [ "$IS_BLOCKING" = "true" ]; then
                ((BLOCKING_FAILED++)) || true
                BLOCKING_FAILURES_ARRAY+=("$FAILURE_OBJ")
            else
                NON_BLOCKING_FAILURES_ARRAY+=("$FAILURE_OBJ")
            fi
        fi
    else
        echo "Warning: Hook script not found: $HOOK_SCRIPT" >&2
    fi
done

# Build JSON arrays
HOOKS_RUN="[$(IFS=,; echo "${HOOKS_RUN_ARRAY[*]}")]"
BLOCKING_FAILURES="[$(IFS=,; echo "${BLOCKING_FAILURES_ARRAY[*]}")]"
NON_BLOCKING_FAILURES="[$(IFS=,; echo "${NON_BLOCKING_FAILURES_ARRAY[*]}")]"

ALL_PASSED="true"
if [ $FAILED -gt 0 ]; then
    ALL_PASSED="false"
fi

# Create .azure directory if needed
AZURE_DIR="$WORKSPACE_PATH/.azure"
mkdir -p "$AZURE_DIR"

# Build final result
RESULT=$(cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "workspace": "$WORKSPACE_PATH",
  "hooks_run": $HOOKS_RUN,
  "all_passed": $ALL_PASSED,
  "blocking_failures": $BLOCKING_FAILURES,
  "non_blocking_failures": $NON_BLOCKING_FAILURES,
  "summary": {
    "total": $TOTAL,
    "passed": $PASSED,
    "failed": $FAILED,
    "blocking_failed": $BLOCKING_FAILED
  }
}
EOF
)

# Write to file
echo "$RESULT" > "$AZURE_DIR/hook-results.json"

# Output to console
echo "$RESULT"

# Exit with appropriate code
if [ $BLOCKING_FAILED -gt 0 ]; then
    exit 1
fi
exit 0
