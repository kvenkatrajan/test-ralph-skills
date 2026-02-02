#!/bin/bash
#
# infra_lint.sh
# Validates Infrastructure as Code (Bicep/Terraform) syntax.
#
# Outputs JSON with hook result

set -e

WORKSPACE_PATH="${1:-$(pwd)}"
INFRA_PATH="$WORKSPACE_PATH/infra"

# Initialize result
HOOK="infra_lint"
STATUS="pass"
BLOCKING="true"
ERROR=""
FIX_SCOPE="[]"
IAC_TYPE=""
FILES_CHECKED="[]"
ERRORS="[]"

# Check if infra directory exists
if [ ! -d "$INFRA_PATH" ]; then
    cat << EOF
{
  "hook": "$HOOK",
  "status": "fail",
  "blocking": $BLOCKING,
  "error": "Infrastructure directory not found at ./infra/",
  "fix_scope": ["infra/"],
  "details": {
    "iac_type": null,
    "files_checked": [],
    "errors": []
  }
}
EOF
    exit 1
fi

# Detect IaC type
BICEP_FILES=$(find "$INFRA_PATH" -name "*.bicep" 2>/dev/null || true)
TF_FILES=$(find "$INFRA_PATH" -name "*.tf" 2>/dev/null || true)

if [ -n "$BICEP_FILES" ]; then
    IAC_TYPE="bicep"
    
    FILES_ARRAY=()
    ERRORS_ARRAY=()
    FIX_ARRAY=()
    
    for file in $BICEP_FILES; do
        REL_PATH="${file#$WORKSPACE_PATH/}"
        FILES_ARRAY+=("\"$REL_PATH\"")
        
        # Check if az bicep is available
        if command -v az &> /dev/null; then
            BUILD_OUTPUT=$(az bicep build --file "$file" 2>&1) || {
                ERRORS_ARRAY+=("{\"file\": \"$REL_PATH\", \"message\": \"$(echo "$BUILD_OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')\"}")
                FIX_ARRAY+=("\"$REL_PATH\"")
            }
        fi
    done
    
    FILES_CHECKED="[$(IFS=,; echo "${FILES_ARRAY[*]}")]"
    
    if [ ${#ERRORS_ARRAY[@]} -gt 0 ]; then
        STATUS="fail"
        ERROR="Infrastructure validation failed with ${#ERRORS_ARRAY[@]} error(s)"
        ERRORS="[$(IFS=,; echo "${ERRORS_ARRAY[*]}")]"
        FIX_SCOPE="[$(IFS=,; echo "${FIX_ARRAY[*]}")]"
    fi

elif [ -n "$TF_FILES" ]; then
    IAC_TYPE="terraform"
    
    FILES_ARRAY=()
    for file in $TF_FILES; do
        REL_PATH="${file#$WORKSPACE_PATH/}"
        FILES_ARRAY+=("\"$REL_PATH\"")
    done
    FILES_CHECKED="[$(IFS=,; echo "${FILES_ARRAY[*]}")]"
    
    # Check if terraform is available
    if command -v terraform &> /dev/null; then
        cd "$INFRA_PATH"
        terraform init -backend=false > /dev/null 2>&1 || true
        VALIDATE_OUTPUT=$(terraform validate -json 2>&1) || true
        
        VALID=$(echo "$VALIDATE_OUTPUT" | jq -r '.valid // true')
        if [ "$VALID" = "false" ]; then
            STATUS="fail"
            ERROR="Terraform validation failed"
            ERRORS=$(echo "$VALIDATE_OUTPUT" | jq '.diagnostics // []')
            # Extract filenames for fix_scope
            FIX_SCOPE=$(echo "$VALIDATE_OUTPUT" | jq '[.diagnostics[]?.range?.filename // empty | "infra/" + .] | unique')
        fi
        cd - > /dev/null
    fi
else
    cat << EOF
{
  "hook": "$HOOK",
  "status": "fail",
  "blocking": $BLOCKING,
  "error": "No Bicep (.bicep) or Terraform (.tf) files found in ./infra/",
  "fix_scope": ["infra/"],
  "details": {
    "iac_type": null,
    "files_checked": [],
    "errors": []
  }
}
EOF
    exit 1
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
    "iac_type": "$IAC_TYPE",
    "files_checked": $FILES_CHECKED,
    "errors": $ERRORS
  }
}
EOF

if [ "$STATUS" = "fail" ]; then
    exit 1
fi
exit 0
