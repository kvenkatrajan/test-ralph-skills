#!/bin/bash
#
# manifest_check.sh
# Validates the Azure preparation manifest for completeness.
#
# Outputs JSON with hook result

set -e

WORKSPACE_PATH="${1:-$(pwd)}"
MANIFEST_PATH="$WORKSPACE_PATH/.azure/preparation-manifest.md"

# Initialize result
HOOK="manifest_check"
STATUS="pass"
BLOCKING="true"
ERROR=""
FIX_SCOPE="[]"
SECTIONS_FOUND="[]"
SECTIONS_MISSING="[]"

# Check if manifest exists
if [ ! -f "$MANIFEST_PATH" ]; then
    STATUS="fail"
    ERROR="Manifest file not found at .azure/preparation-manifest.md"
    FIX_SCOPE='[".azure/preparation-manifest.md"]'
    
    cat << EOF
{
  "hook": "$HOOK",
  "status": "$STATUS",
  "blocking": $BLOCKING,
  "error": "$ERROR",
  "fix_scope": $FIX_SCOPE,
  "details": {
    "sections_found": $SECTIONS_FOUND,
    "sections_missing": $SECTIONS_MISSING
  }
}
EOF
    exit 1
fi

# Read manifest content
CONTENT=$(cat "$MANIFEST_PATH")

# Required sections
REQUIRED_SECTIONS=("Requirements" "Components" "Recipe" "Architecture" "Generated Files")
FOUND=()
MISSING=()

for section in "${REQUIRED_SECTIONS[@]}"; do
    if echo "$CONTENT" | grep -q "## $section"; then
        FOUND+=("\"$section\"")
    else
        MISSING+=("\"$section\"")
    fi
done

# Required fields in Requirements
REQUIRED_FIELDS=("Classification" "Scale" "Budget" "Region")
MISSING_FIELDS=()

for field in "${REQUIRED_FIELDS[@]}"; do
    if ! echo "$CONTENT" | grep -q "$field"; then
        MISSING_FIELDS+=("\"$field\"")
    fi
done

# Build JSON arrays
SECTIONS_FOUND="[$(IFS=,; echo "${FOUND[*]}")]"
SECTIONS_MISSING="[$(IFS=,; echo "${MISSING[*]}")]"

# Determine pass/fail
if [ ${#MISSING[@]} -gt 0 ]; then
    STATUS="fail"
    ERROR="Missing required sections: $(IFS=', '; echo "${MISSING[*]}" | tr -d '"')"
    FIX_SCOPE='[".azure/preparation-manifest.md"]'
elif [ ${#MISSING_FIELDS[@]} -gt 0 ]; then
    STATUS="fail"
    ERROR="Missing required fields in Requirements: $(IFS=', '; echo "${MISSING_FIELDS[*]}" | tr -d '"')"
    FIX_SCOPE='[".azure/preparation-manifest.md"]'
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
    "sections_found": $SECTIONS_FOUND,
    "sections_missing": $SECTIONS_MISSING
  }
}
EOF

if [ "$STATUS" = "fail" ]; then
    exit 1
fi
exit 0
