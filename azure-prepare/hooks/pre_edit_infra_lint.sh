#!/bin/bash
#
# pre_edit_infra_lint.sh
# Pre-tool use hook - validates IaC syntax before allowing infra edits.
# Triggered by GitHub Copilot BEFORE edit operations on infra/ files.

set -e

# Read input from stdin (Copilot hook format)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs')

# Only check edit operations
case "$TOOL_NAME" in
    edit|create|write_file|create_file|replace_string_in_file)
        ;;
    *)
        exit 0
        ;;
esac

# Get file path
FILE_PATH=""
if echo "$TOOL_ARGS" | jq -e '.path' > /dev/null 2>&1; then
    FILE_PATH=$(echo "$TOOL_ARGS" | jq -r '.path')
elif echo "$TOOL_ARGS" | jq -e '.filePath' > /dev/null 2>&1; then
    FILE_PATH=$(echo "$TOOL_ARGS" | jq -r '.filePath')
elif echo "$TOOL_ARGS" | jq -e '.file' > /dev/null 2>&1; then
    FILE_PATH=$(echo "$TOOL_ARGS" | jq -r '.file')
fi

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only check infra files
if [[ ! "$FILE_PATH" =~ infra/.+\.(bicep|tf)$ ]]; then
    exit 0
fi

# Get content
CONTENT=""
if echo "$TOOL_ARGS" | jq -e '.content' > /dev/null 2>&1; then
    CONTENT=$(echo "$TOOL_ARGS" | jq -r '.content')
elif echo "$TOOL_ARGS" | jq -e '.newString' > /dev/null 2>&1; then
    CONTENT=$(echo "$TOOL_ARGS" | jq -r '.newString')
fi

if [ -z "$CONTENT" ]; then
    exit 0
fi

ISSUES=""

# For Bicep files
if [[ "$FILE_PATH" =~ \.bicep$ ]]; then
    # Check for unclosed braces
    OPEN_BRACES=$(echo "$CONTENT" | grep -o '{' | wc -l)
    CLOSE_BRACES=$(echo "$CONTENT" | grep -o '}' | wc -l)
    
    if [ "$OPEN_BRACES" -ne "$CLOSE_BRACES" ]; then
        ISSUES="Unbalanced braces (open: $OPEN_BRACES, close: $CLOSE_BRACES)"
    fi
    
    # Check for param without type
    if echo "$CONTENT" | grep -qE "param[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*="; then
        if [ -n "$ISSUES" ]; then ISSUES="$ISSUES; "; fi
        ISSUES="${ISSUES}Parameter missing type annotation"
    fi
fi

# For Terraform files
if [[ "$FILE_PATH" =~ \.tf$ ]]; then
    # Check for unclosed braces
    OPEN_BRACES=$(echo "$CONTENT" | grep -o '{' | wc -l)
    CLOSE_BRACES=$(echo "$CONTENT" | grep -o '}' | wc -l)
    
    if [ "$OPEN_BRACES" -ne "$CLOSE_BRACES" ]; then
        ISSUES="Unbalanced braces"
    fi
fi

if [ -n "$ISSUES" ]; then
    jq -n --arg reason "IaC syntax issues: $ISSUES" \
        '{permissionDecision: "deny", permissionDecisionReason: $reason}'
    exit 0
fi

# Allow the edit
exit 0
