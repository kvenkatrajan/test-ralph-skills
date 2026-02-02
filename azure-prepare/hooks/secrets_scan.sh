#!/bin/bash
#
# secrets_scan.sh
# Scans generated files for hardcoded secrets.
#
# Outputs JSON with hook result

set -e

WORKSPACE_PATH="${1:-$(pwd)}"

# Initialize result
HOOK="secrets_scan"
STATUS="pass"
BLOCKING="true"
ERROR=""
FIX_SCOPE="[]"
FILES_SCANNED=0
SECRETS_FOUND="[]"

# Secret patterns (simplified for grep -E)
SECRET_PATTERNS=(
    "AccountKey=[A-Za-z0-9+/=]{88}"
    "(api[_-]?key|apikey)[[:space:]]*[=:][[:space:]]*['\"][A-Za-z0-9]{20,}['\"]"
    "(password|passwd|pwd)[[:space:]]*[=:][[:space:]]*['\"][^'\"]{8,}['\"]"
    "Bearer[[:space:]]+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"
    "-----BEGIN[[:space:]]+(RSA[[:space:]]|EC[[:space:]]|DSA[[:space:]]|OPENSSH[[:space:]])?PRIVATE[[:space:]]+KEY-----"
    "(client[_-]?secret)[[:space:]]*[=:][[:space:]]*['\"][A-Za-z0-9~._-]{34,}['\"]"
    "secret[[:space:]]*[=:][[:space:]]*['\"][A-Za-z0-9]{16,}['\"]"
)

PATTERN_NAMES=(
    "Azure Connection String"
    "API Key Pattern"
    "Password in Config"
    "Bearer Token"
    "Private Key"
    "Azure AD Client Secret"
    "Generic Secret"
)

# Directories to scan
DIRS_TO_SCAN=("infra" "src" ".azure")

# File extensions to scan
EXTENSIONS="bicep|tf|yaml|yml|json|ps1|sh|py|js|ts|cs|config|env"

SECRETS_ARRAY=()
FIX_ARRAY=()
declare -A FILES_WITH_SECRETS

for dir in "${DIRS_TO_SCAN[@]}"; do
    DIR_PATH="$WORKSPACE_PATH/$dir"
    
    if [ -d "$DIR_PATH" ]; then
        # Find files with matching extensions
        FILES=$(find "$DIR_PATH" -type f -regextype posix-extended -regex ".*\.($EXTENSIONS)$" 2>/dev/null || true)
        
        for file in $FILES; do
            ((FILES_SCANNED++)) || true
            REL_PATH="${file#$WORKSPACE_PATH/}"
            
            for i in "${!SECRET_PATTERNS[@]}"; do
                PATTERN="${SECRET_PATTERNS[$i]}"
                PATTERN_NAME="${PATTERN_NAMES[$i]}"
                
                # Search for pattern in file
                MATCHES=$(grep -nE -i "$PATTERN" "$file" 2>/dev/null || true)
                
                if [ -n "$MATCHES" ]; then
                    LINE_NUM=$(echo "$MATCHES" | head -1 | cut -d: -f1)
                    SECRETS_ARRAY+=("{\"file\": \"$REL_PATH\", \"line\": $LINE_NUM, \"type\": \"$PATTERN_NAME\"}")
                    
                    if [ -z "${FILES_WITH_SECRETS[$REL_PATH]}" ]; then
                        FILES_WITH_SECRETS[$REL_PATH]=1
                        FIX_ARRAY+=("\"$REL_PATH\"")
                    fi
                fi
            done
        done
    fi
done

# Build JSON arrays
if [ ${#SECRETS_ARRAY[@]} -gt 0 ]; then
    STATUS="fail"
    ERROR="Found ${#SECRETS_ARRAY[@]} potential hardcoded secret(s)"
    SECRETS_FOUND="[$(IFS=,; echo "${SECRETS_ARRAY[*]}")]"
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
    "files_scanned": $FILES_SCANNED,
    "secrets_found": $SECRETS_FOUND
  }
}
EOF

if [ "$STATUS" = "fail" ]; then
    exit 1
fi
exit 0
