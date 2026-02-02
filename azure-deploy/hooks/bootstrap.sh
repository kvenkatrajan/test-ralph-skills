#!/bin/bash
#
# Bootstrap script to install azure-deploy hooks into the workspace.
#
# Copies hook scripts and configuration from the skill directory
# to the workspace's .github/hooks directory.
#
# Usage: ./bootstrap.sh <workspace_path>
#

set -e

WORKSPACE_PATH="${1:-.}"

echo "Installing azure-deploy hooks to workspace..."

# Determine skill directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_SOURCE_DIR="$SKILL_DIR/hooks"

# Target directories
GITHUB_DIR="$WORKSPACE_PATH/.github"
HOOKS_BASE_DIR="$GITHUB_DIR/hooks"
HOOKS_TARGET_DIR="$HOOKS_BASE_DIR/azure-deploy"

# Create directories
if [ ! -d "$GITHUB_DIR" ]; then
    mkdir -p "$GITHUB_DIR"
    echo "  Created .github directory"
fi

if [ ! -d "$HOOKS_BASE_DIR" ]; then
    mkdir -p "$HOOKS_BASE_DIR"
    echo "  Created .github/hooks directory"
fi

if [ ! -d "$HOOKS_TARGET_DIR" ]; then
    mkdir -p "$HOOKS_TARGET_DIR"
    echo "  Created .github/hooks/azure-deploy directory"
fi

# Copy/merge hooks.json
HOOKS_JSON_SOURCE="$SKILL_DIR/hooks.json"
HOOKS_JSON_TARGET="$GITHUB_DIR/hooks.json"

if [ -f "$HOOKS_JSON_SOURCE" ]; then
    if [ -f "$HOOKS_JSON_TARGET" ]; then
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
        ' "$HOOKS_JSON_TARGET" "$HOOKS_JSON_SOURCE" > "$HOOKS_JSON_TARGET.tmp"
        
        if [ $? -eq 0 ]; then
            mv "$HOOKS_JSON_TARGET.tmp" "$HOOKS_JSON_TARGET"
            echo "  Merged hooks.json"
        else
            # jq not available or failed, warn user
            echo "WARNING: Could not merge hooks.json (jq required). Existing file preserved."
            echo "  Please manually merge hooks from: $HOOKS_JSON_SOURCE"
            rm -f "$HOOKS_JSON_TARGET.tmp"
        fi
    else
        # No existing file, just copy
        cp "$HOOKS_JSON_SOURCE" "$HOOKS_JSON_TARGET"
        echo "  Copied hooks.json"
    fi
else
    echo "WARNING: hooks.json not found at $HOOKS_JSON_SOURCE"
fi

# Copy all hook scripts
HOOK_SCRIPTS=(
    "session_init.ps1"
    "session_init.sh"
    "pre_deploy_auth_check.ps1"
    "pre_deploy_auth_check.sh"
    "pre_deploy_manifest_check.ps1"
    "pre_deploy_manifest_check.sh"
    "pre_deploy_env_check.ps1"
    "pre_deploy_env_check.sh"
    "post_deploy_capture.ps1"
    "post_deploy_capture.sh"
    "post_deploy_verify.ps1"
    "post_deploy_verify.sh"
    "session_complete.ps1"
    "session_complete.sh"
    "run_hooks.ps1"
    "run_hooks.sh"
)

for script in "${HOOK_SCRIPTS[@]}"; do
    SOURCE="$HOOKS_SOURCE_DIR/$script"
    TARGET="$HOOKS_TARGET_DIR/$script"
    
    if [ -f "$SOURCE" ]; then
        cp "$SOURCE" "$TARGET"
        chmod +x "$TARGET"
        echo "  Copied $script"
    else
        echo "WARNING: Hook script not found: $script"
    fi
done

# Create .azure directory if it doesn't exist
AZURE_DIR="$WORKSPACE_PATH/.azure"
if [ ! -d "$AZURE_DIR" ]; then
    mkdir -p "$AZURE_DIR"
    echo "  Created .azure directory"
fi

echo ""
echo "========================================"
echo "Hook Installation Complete!"
echo "========================================"
echo ""
echo "Installed to:"
echo "  - $HOOKS_JSON_TARGET"
echo "  - $HOOKS_TARGET_DIR/"
echo ""
echo "Hooks will be loaded from: .github/hooks/azure-deploy/"
echo ""
echo "You can now proceed with deployment."
