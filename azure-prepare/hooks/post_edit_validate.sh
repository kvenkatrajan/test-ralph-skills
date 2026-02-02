#!/bin/bash
#
# post_edit_validate.sh
# Post-tool use hook - runs full validation after edits complete.
# Triggered by GitHub Copilot AFTER any tool completes.

set -e

# Read input from stdin (Copilot hook format)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
RESULT_TYPE=$(echo "$INPUT" | jq -r '.toolResult.resultType')
CWD=$(echo "$INPUT" | jq -r '.cwd')

# Only validate after edit operations
case "$TOOL_NAME" in
    edit|create|write_file|create_file|replace_string_in_file|bash)
        ;;
    *)
        exit 0
        ;;
esac

# Only proceed if the tool succeeded
if [ "$RESULT_TYPE" != "success" ]; then
    exit 0
fi

AZURE_DIR="$CWD/.azure"
MANIFEST_PATH="$AZURE_DIR/preparation-manifest.md"
HOOK_RESULTS_PATH="$AZURE_DIR/hook-results.json"

# Ensure .azure directory exists
mkdir -p "$AZURE_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CHECKS="[]"

# Check 1: Manifest exists
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CHECK='{"name":"manifest_exists","passed":true,"message":"Manifest found"}'
else
    MANIFEST_CHECK='{"name":"manifest_exists","passed":false,"message":"Manifest not found"}'
fi

# Check 2: Infra directory exists
if [ -d "$CWD/infra" ]; then
    INFRA_CHECK='{"name":"infra_directory","passed":true,"message":"Infrastructure directory found"}'
else
    INFRA_CHECK='{"name":"infra_directory","passed":false,"message":"No infra/ directory yet"}'
fi

# Check 3: Scan for secrets in recent files
SECRETS_FOUND="false"
SECRETS_MSG="No hardcoded secrets detected"

# Find recently modified files (last 5 minutes)
RECENT_FILES=$(find "$CWD" -type f \( -name "*.bicep" -o -name "*.tf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) -mmin -5 2>/dev/null || true)

for file in $RECENT_FILES; do
    if grep -qE "AccountKey=[A-Za-z0-9+/=]{88}|-----BEGIN.*PRIVATE KEY-----|password[[:space:]]*[=:][[:space:]]*['\"][^'\"]{8,}['\"]" "$file" 2>/dev/null; then
        SECRETS_FOUND="true"
        SECRETS_MSG="Potential secret in: $(basename "$file")"
        break
    fi
done

if [ "$SECRETS_FOUND" = "true" ]; then
    SECRETS_CHECK="{\"name\":\"secrets_scan\",\"passed\":false,\"message\":\"$SECRETS_MSG\"}"
else
    SECRETS_CHECK='{"name":"secrets_scan","passed":true,"message":"No hardcoded secrets detected"}'
fi

# Build results JSON
cat > "$HOOK_RESULTS_PATH" << EOF
{
  "timestamp": "$TIMESTAMP",
  "trigger": "post_edit",
  "toolName": "$TOOL_NAME",
  "checks": [
    $MANIFEST_CHECK,
    $INFRA_CHECK,
    $SECRETS_CHECK
  ],
  "allPassed": $([ "$SECRETS_FOUND" = "false" ] && echo "true" || echo "false")
}
EOF

# Log to session log
LOG_PATH="$AZURE_DIR/session.log"
echo "$TIMESTAMP: Post-edit validation completed" >> "$LOG_PATH"

# Post-tool hook output is ignored by Copilot
exit 0
