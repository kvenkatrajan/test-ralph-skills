#!/bin/bash
#
# SYNOPSIS
#     Copies hooks infrastructure to workspace to enable Ralph Wiggum loop.
#
# DESCRIPTION
#     This script must be run BEFORE any other azure-prepare operations.
#     It copies hooks.json and the hooks directory to the workspace,
#     enabling the CLI's native hook system to enforce validations.
#     Hooks are installed to .github/hooks/azure-prepare/ to avoid conflicts.
#
# USAGE
#     ./bootstrap.sh [workspace_path]
#

set -e

WORKSPACE_PATH="${1:-$(pwd)}"

# Get skill directory (parent of hooks directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Paths - use .github/hooks/azure-prepare directory for skill isolation
GITHUB_DIR="$WORKSPACE_PATH/.github"
HOOKS_BASE_DIR="$GITHUB_DIR/hooks"
DEST_HOOKS_DIR="$HOOKS_BASE_DIR/azure-prepare"
SOURCE_HOOKS_JSON="$SKILL_DIR/hooks.json"
SOURCE_HOOKS_DIR="$SKILL_DIR/hooks"
# Main hooks.json in .github/ that merges all skill hooks
DEST_HOOKS_JSON="$GITHUB_DIR/hooks.json"

# Create .github directory if needed
if [ ! -d "$GITHUB_DIR" ]; then
    mkdir -p "$GITHUB_DIR"
    echo "✓ Created .github directory"
fi

# Create .github/hooks directory if needed
if [ ! -d "$HOOKS_BASE_DIR" ]; then
    mkdir -p "$HOOKS_BASE_DIR"
    echo "✓ Created .github/hooks directory"
fi

# Create .github/hooks/azure-prepare directory if needed
if [ ! -d "$DEST_HOOKS_DIR" ]; then
    mkdir -p "$DEST_HOOKS_DIR"
    echo "✓ Created .github/hooks/azure-prepare directory"
fi

# Copy hooks directory contents to skill-specific folder
if [ -d "$SOURCE_HOOKS_DIR" ]; then
    # Copy all hook scripts to .github/hooks/azure-prepare/
    cp -f "$SOURCE_HOOKS_DIR"/* "$DEST_HOOKS_DIR/" 2>/dev/null || true
    echo "✓ Copied hook scripts to .github/hooks/azure-prepare/"
else
    echo "Error: hooks directory not found at $SOURCE_HOOKS_DIR" >&2
    exit 1
fi

# Merge hooks.json with existing (if present)
if [ -f "$SOURCE_HOOKS_JSON" ]; then
    if [ -f "$DEST_HOOKS_JSON" ]; then
        # Merge with existing hooks.json
        echo "  Merging with existing hooks.json..."
        
        # Use jq to merge hooks arrays, avoiding duplicates by checking bash/powershell paths
        jq -s '
          def merge_hooks(type):
            (.[0].hooks[type] // []) as $existing |
            (.[1].hooks[type] // []) as $new |
            $existing + [$new[] | select(
              . as $n | $existing | map(
                .bash == $n.bash or .powershell == $n.powershell
              ) | any | not
            )];
          
          .[0] * {
            hooks: {
              sessionStart: merge_hooks("sessionStart"),
              preToolUse: merge_hooks("preToolUse"),
              postToolUse: merge_hooks("postToolUse"),
              sessionEnd: merge_hooks("sessionEnd")
            }
          }
        ' "$DEST_HOOKS_JSON" "$SOURCE_HOOKS_JSON" > "$DEST_HOOKS_JSON.tmp"
        
        if [ $? -eq 0 ]; then
            mv "$DEST_HOOKS_JSON.tmp" "$DEST_HOOKS_JSON"
            echo "✓ Merged hooks.json"
        else
            # jq not available or failed, warn user
            echo "WARNING: Could not merge hooks.json (jq required). Existing file preserved."
            echo "  Please manually merge hooks from: $SOURCE_HOOKS_JSON"
            rm -f "$DEST_HOOKS_JSON.tmp"
        fi
    else
        # No existing file, just copy
        cp -f "$SOURCE_HOOKS_JSON" "$DEST_HOOKS_JSON"
        echo "✓ Copied hooks.json to .github/"
    fi
else
    echo "Error: hooks.json not found at $SOURCE_HOOKS_JSON" >&2
    exit 1
fi

# Create .azure directory if needed
AZURE_DIR="$WORKSPACE_PATH/.azure"
if [ ! -d "$AZURE_DIR" ]; then
    mkdir -p "$AZURE_DIR"
    echo "✓ Created .azure directory"
fi

echo ""
echo "Ralph Wiggum loop hooks installed successfully."
echo "Location: .github/hooks/azure-prepare/"
echo ""
echo "The following hooks are now active:"
echo "  - sessionStart: session_init"
echo "  - preToolUse: pre_edit_secrets_scan, pre_edit_infra_lint"
echo "  - postToolUse: post_edit_validate"
echo "  - sessionEnd: session_complete"
echo ""
echo "Run '.github/hooks/azure-prepare/run_hooks.sh' to manually execute all validation hooks."

exit 0
