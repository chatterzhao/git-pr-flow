#!/bin/bash

set -euo pipefail

# Source the required files
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils/git.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils/environment.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils/paths.sh"

# Global variable
declare -a EPIC_MATCHES=()

# Test the find function
find_epic_by_name() {
    local user_input="$1"
    
    # Method 1: Direct match (if user input contains epic/ prefix)
    if [[ "$user_input" == epic/* ]]; then
        local epic_name="${user_input#epic/}"
        if git branch | grep -q "epic/$epic_name"; then
            echo "$epic_name"
            return 0
        fi
    fi
    
    # Method 2: Auto-add epic/ prefix match
    if git branch | grep -q "epic/$user_input"; then
        echo "$user_input"
        return 0
    fi
    
    # Method 3: Fuzzy match (partial match)
    local epic_branches
    epic_branches=$(git branch 2>/dev/null | grep "epic/" | sed 's/^[* +] *//' || echo "")
    
    local matches=()
    if [[ -n "$epic_branches" ]]; then
        while IFS= read -r epic_branch; do
            if [[ -n "$epic_branch" ]]; then
                local epic_name="${epic_branch#epic/}"
                # Check if contains user input string
                if [[ "$epic_name" == *"$user_input"* ]]; then
                    matches+=("$epic_name")
                fi
            fi
        done <<< "$epic_branches"
    fi
    
    # If only one match, return it
    if [[ ${#matches[@]} -eq 1 ]]; then
        echo "${matches[0]}"
        return 0
    fi
    
    # If multiple matches, store to global variable for error hint
    if [[ ${#matches[@]} -gt 0 ]]; then
        EPIC_MATCHES=("${matches[@]}")
    else
        EPIC_MATCHES=()
    fi
    
    return 1
}

# Test the error function
show_epic_not_found_error() {
    local user_input="$1"
    
    ui_error "Epic '$user_input' 不存在"
    echo
    
    # Check if there are multiple match suggestions
    if [[ "${#EPIC_MATCHES[@]}" -gt 1 ]]; then
        echo "🔍 找到多个可能的匹配:"
        for match in "${EPIC_MATCHES[@]}"; do
            echo "  • $match"
        done
        echo
        echo "💡 请使用更具体的名称，如: gpf status ${EPIC_MATCHES[0]}"
        echo
    fi
    
    echo "💡 可用的Epic:"
    echo "  Testing..."
    echo
    echo "📋 Epic管理命令:"
    echo "  gpf init <epic-name>          # 创建新Epic"
    echo "  gpf status                    # 查看所有Epic概览"
}

echo "Testing find_epic_by_name with 'invalid-epic'..."
if epic_name=$(find_epic_by_name "invalid-epic"); then
    echo "Found: $epic_name"
else
    echo "Not found, calling error function..."
    show_epic_not_found_error "invalid-epic"
fi