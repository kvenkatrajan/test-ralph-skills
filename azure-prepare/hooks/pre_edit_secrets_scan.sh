#!/bin/bash
#
# pre_edit_secrets_scan.sh
# Pre-tool use hook - blocks edits that would introduce hardcoded secrets.
# Triggered by GitHub Copilot BEFORE any tool use.

set -e

# Read input from stdin (Copilot hook format)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs')

# Only check edit and create operations
case "$TOOL_NAME" in
    edit|create|write_file|create_file|replace_string_in_file)
        ;;
    *)
        # Allow non-edit tools
        exit 0
        ;;
esac

# Get content to check
CONTENT=""
if echo "$TOOL_ARGS" | jq -e '.content' > /dev/null 2>&1; then
    CONTENT=$(echo "$TOOL_ARGS" | jq -r '.content')
elif echo "$TOOL_ARGS" | jq -e '.newString' > /dev/null 2>&1; then
    CONTENT=$(echo "$TOOL_ARGS" | jq -r '.newString')
elif echo "$TOOL_ARGS" | jq -e '.text' > /dev/null 2>&1; then
    CONTENT=$(echo "$TOOL_ARGS" | jq -r '.text')
fi

if [ -z "$CONTENT" ]; then
    # No content to check, allow
    exit 0
fi

# Secret patterns to detect
PATTERNS=(
    "AccountKey=[A-Za-z0-9+/=]{88}:Azure Storage Key"
    "(api[_-]?key|apikey)[[:space:]]*[=:][[:space:]]*['\"][A-Za-z0-9]{20,}['\"]|API Key"
    "(password|passwd|pwd)[[:space:]]*[=:][[:space:]]*['\"][^'\"]{8,}['\"]|Password"
    "Bearer[[:space:]]+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|Bearer Token"
    "-----BEGIN[[:space:]]+(RSA[[:space:]]|EC[[:space:]]|DSA[[:space:]]|OPENSSH[[:space:]])?PRIVATE[[:space:]]+KEY-----|Private Key"
    "(client[_-]?secret)[[:space:]]*[=:][[:space:]]*['\"][A-Za-z0-9~._-]{34,}['\"]|Client Secret"
)

# Check content for secrets
for pattern_def in "${PATTERNS[@]}"; do
    PATTERN="${pattern_def%%|*}"
    NAME="${pattern_def##*|}"
    
    if echo "$CONTENT" | grep -qEi "$PATTERN"; then
        # DENY - secret detected
        jq -n --arg reason "Hardcoded secret detected: $NAME. Use Key Vault or environment variables instead." \
            '{permissionDecision: "deny", permissionDecisionReason: $reason}'
        exit 0
    fi
done

# No secrets found - allow (no output means allow)
exit 0
