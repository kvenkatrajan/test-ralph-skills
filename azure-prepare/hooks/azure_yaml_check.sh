#!/bin/bash
#
# azure_yaml_check.sh
# Validates azure.yaml structure for AZD projects.
#
# Outputs JSON with hook result

set -e

WORKSPACE_PATH="${1:-$(pwd)}"
AZURE_YAML_PATH="$WORKSPACE_PATH/azure.yaml"
MANIFEST_PATH="$WORKSPACE_PATH/.azure/preparation-manifest.md"

# Initialize result
HOOK="azure_yaml_check"
STATUS="pass"
BLOCKING="true"
ERROR=""
FIX_SCOPE="[]"
AZURE_YAML_EXISTS="false"
SERVICES_DEFINED="[]"
MISSING_FIELDS="[]"
VALIDATION_ERRORS="[]"

# Check if this is an AZD project
IS_AZD_PROJECT="false"
if [ -f "$MANIFEST_PATH" ]; then
    if grep -qiE "recipe.*azd|selected.*azd" "$MANIFEST_PATH" 2>/dev/null; then
        IS_AZD_PROJECT="true"
    fi
fi

# If not AZD project and no azure.yaml, skip
if [ "$IS_AZD_PROJECT" = "false" ] && [ ! -f "$AZURE_YAML_PATH" ]; then
    cat << EOF
{
  "hook": "$HOOK",
  "status": "pass",
  "blocking": $BLOCKING,
  "error": null,
  "fix_scope": [],
  "details": {
    "azure_yaml_exists": false,
    "services_defined": [],
    "missing_fields": [],
    "validation_errors": ["Not an AZD project - azure.yaml check skipped"]
  }
}
EOF
    exit 0
fi

# Check if azure.yaml exists
if [ ! -f "$AZURE_YAML_PATH" ]; then
    cat << EOF
{
  "hook": "$HOOK",
  "status": "fail",
  "blocking": $BLOCKING,
  "error": "azure.yaml not found but AZD recipe is selected",
  "fix_scope": ["azure.yaml"],
  "details": {
    "azure_yaml_exists": false,
    "services_defined": [],
    "missing_fields": [],
    "validation_errors": []
  }
}
EOF
    exit 1
fi

AZURE_YAML_EXISTS="true"
CONTENT=$(cat "$AZURE_YAML_PATH")

# Check required fields
MISSING_ARRAY=()
ERRORS_ARRAY=()
SERVICES_ARRAY=()

# Check for 'name' field
if ! echo "$CONTENT" | grep -qE "^name[[:space:]]*:"; then
    MISSING_ARRAY+=("\"name\"")
fi

# Check for 'services' field
if ! echo "$CONTENT" | grep -qE "^services[[:space:]]*:"; then
    MISSING_ARRAY+=("\"services\"")
else
    # Extract service names (lines that start with 2 spaces followed by word and colon)
    SERVICES=$(echo "$CONTENT" | grep -E "^  [a-zA-Z][a-zA-Z0-9_-]*:" | sed 's/^  //' | cut -d: -f1)
    
    for service in $SERVICES; do
        SERVICES_ARRAY+=("\"$service\"")
        
        # Check if service has 'host' field
        # This is a simplified check
        SERVICE_SECTION=$(echo "$CONTENT" | sed -n "/^  $service:/,/^  [a-zA-Z]/p" | head -n -1)
        if ! echo "$SERVICE_SECTION" | grep -qE "host[[:space:]]*:"; then
            ERRORS_ARRAY+=("\"Service '$service' missing 'host' field\"")
        fi
    done
fi

# Build JSON arrays
SERVICES_DEFINED="[$(IFS=,; echo "${SERVICES_ARRAY[*]}")]"
MISSING_FIELDS="[$(IFS=,; echo "${MISSING_ARRAY[*]}")]"
VALIDATION_ERRORS="[$(IFS=,; echo "${ERRORS_ARRAY[*]}")]"

# Determine status
if [ ${#MISSING_ARRAY[@]} -gt 0 ]; then
    STATUS="fail"
    ERROR="azure.yaml missing required fields: $(IFS=', '; echo "${MISSING_ARRAY[*]}" | tr -d '"')"
    FIX_SCOPE='["azure.yaml"]'
elif [ ${#ERRORS_ARRAY[@]} -gt 0 ]; then
    STATUS="fail"
    ERROR="azure.yaml validation failed"
    FIX_SCOPE='["azure.yaml"]'
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
    "azure_yaml_exists": $AZURE_YAML_EXISTS,
    "services_defined": $SERVICES_DEFINED,
    "missing_fields": $MISSING_FIELDS,
    "validation_errors": $VALIDATION_ERRORS
  }
}
EOF

if [ "$STATUS" = "fail" ]; then
    exit 1
fi
exit 0
