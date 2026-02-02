#!/bin/bash
#
# dockerfile_lint.sh
# Validates Dockerfile best practices.
# This is a non-blocking hook - failures are warnings.
#
# Outputs JSON with hook result

set -e

WORKSPACE_PATH="${1:-$(pwd)}"

# Initialize result
HOOK="dockerfile_lint"
STATUS="pass"
BLOCKING="false"  # Non-blocking hook
ERROR=""
FIX_SCOPE="[]"
DOCKERFILES_FOUND="[]"
WARNINGS="[]"
VIOLATIONS="[]"

# Find all Dockerfiles
DOCKERFILES=$(find "$WORKSPACE_PATH" -name "Dockerfile*" -type f 2>/dev/null || true)

if [ -z "$DOCKERFILES" ]; then
    # No Dockerfiles is not a failure for this hook
    cat << EOF
{
  "hook": "$HOOK",
  "status": "pass",
  "blocking": $BLOCKING,
  "error": null,
  "fix_scope": [],
  "details": {
    "dockerfiles_found": [],
    "warnings": [],
    "best_practices_violations": []
  }
}
EOF
    exit 0
fi

DOCKERFILES_ARRAY=()
VIOLATIONS_ARRAY=()
WARNINGS_ARRAY=()
FIX_ARRAY=()
ERROR_COUNT=0

for dockerfile in $DOCKERFILES; do
    REL_PATH="${dockerfile#$WORKSPACE_PATH/}"
    DOCKERFILES_ARRAY+=("\"$REL_PATH\"")
    
    CONTENT=$(cat "$dockerfile" 2>/dev/null || true)
    
    # Check: Use specific base image tag (not :latest)
    if echo "$CONTENT" | grep -qE "FROM[[:space:]]+[^:]+:latest"; then
        VIOLATIONS_ARRAY+=("{\"file\": \"$REL_PATH\", \"check\": \"Use specific base image tag\", \"message\": \"Avoid using ':latest' tag - use specific version tags\", \"severity\": \"warning\"}")
        WARNINGS_ARRAY+=("\"$REL_PATH: Avoid using ':latest' tag\"")
    fi
    
    # Check: No secrets in ENV
    if echo "$CONTENT" | grep -qEi "ENV[[:space:]]+.*(PASSWORD|SECRET|KEY|TOKEN)[[:space:]]*="; then
        VIOLATIONS_ARRAY+=("{\"file\": \"$REL_PATH\", \"check\": \"No secrets in ENV\", \"message\": \"Avoid hardcoding secrets in ENV instructions\", \"severity\": \"error\"}")
        FIX_ARRAY+=("\"$REL_PATH\"")
        ((ERROR_COUNT++)) || true
    fi
    
    # Check: Use COPY instead of ADD for local files
    if echo "$CONTENT" | grep -qE "ADD[[:space:]]+[^h]"; then
        VIOLATIONS_ARRAY+=("{\"file\": \"$REL_PATH\", \"check\": \"Use COPY instead of ADD\", \"message\": \"Use COPY instead of ADD for local files\", \"severity\": \"info\"}")
    fi
    
    # Check: HEALTHCHECK defined
    if ! echo "$CONTENT" | grep -q "HEALTHCHECK"; then
        VIOLATIONS_ARRAY+=("{\"file\": \"$REL_PATH\", \"check\": \"Health check defined\", \"message\": \"Consider adding HEALTHCHECK instruction\", \"severity\": \"info\"}")
    fi
done

# Build JSON arrays
DOCKERFILES_FOUND="[$(IFS=,; echo "${DOCKERFILES_ARRAY[*]}")]"
VIOLATIONS="[$(IFS=,; echo "${VIOLATIONS_ARRAY[*]}")]"
WARNINGS="[$(IFS=,; echo "${WARNINGS_ARRAY[*]}")]"

if [ $ERROR_COUNT -gt 0 ]; then
    STATUS="fail"
    ERROR="Found $ERROR_COUNT Dockerfile best practice error(s)"
    FIX_SCOPE="[$(IFS=,; echo "${FIX_ARRAY[*]}")]"
fi

# Output JSON result
cat << EOF
{
  "hook": "$HOOK",
  "status": "$STATUS",
  "blocking": $BLOCKING,
  "error": $([ -n "$ERROR" ] && echo "\"$ERROR\"" || echo "null"),
  "fix_scope": $FIX_SCOPE,
  "details": {
    "dockerfiles_found": $DOCKERFILES_FOUND,
    "warnings": $WARNINGS,
    "best_practices_violations": $VIOLATIONS
  }
}
EOF

if [ "$STATUS" = "fail" ]; then
    exit 1
fi
exit 0
