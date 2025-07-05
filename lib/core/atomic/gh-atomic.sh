#!/bin/bash
# GPF Core - GitHub CLI Atomic Methods
# GitHub CLI原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 检查GitHub CLI是否已安装
# 返回：0（已安装）或1（未安装）
gh_check_installation() {
    command -v gh >/dev/null 2>&1
}

# 获取GitHub CLI版本
# 返回：版本字符串 或 空字符串（未安装）
gh_get_version() {
    if gh_check_installation; then
        gh --version 2>/dev/null | head -n1 | awk '{print $3}' || echo ""
    else
        echo ""
    fi
}

# 检查GitHub CLI认证状态
# 返回：0（已认证）或1（未认证）
gh_check_auth() {
    if ! gh_check_installation; then
        return 1
    fi
    
    gh auth status >/dev/null 2>&1
}

# 获取当前认证用户信息
# 返回：用户名 或 空字符串（未认证）
gh_get_current_user() {
    if gh_check_auth; then
        gh api user --jq '.login' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# 检查当前仓库是否支持GitHub操作
# 参数：(optional: worktree_path)
# 返回：0（支持）或1（不支持）
gh_check_repo_support() {
    local worktree_path="${1:-$(pwd)}"
    
    if ! gh_check_installation; then
        return 1
    fi
    
    # 检查是否在Git仓库中
    if ! git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1; then
        return 1
    fi
    
    # 检查是否有GitHub远程仓库
    local remote_url
    remote_url=$(git -C "$worktree_path" remote get-url origin 2>/dev/null || echo "")
    
    if [[ "$remote_url" =~ github\.com ]]; then
        return 0
    else
        return 1
    fi
}

# 获取仓库信息
# 参数：(optional: worktree_path)
# 返回：JSON格式的仓库信息
gh_get_repo_info() {
    local worktree_path="${1:-$(pwd)}"
    
    if ! gh_check_repo_support "$worktree_path"; then
        cat << EOF
{
    "supported": false,
    "owner": null,
    "name": null,
    "url": null,
    "error": "Repository not supported or not a GitHub repo"
}
EOF
        return 1
    fi
    
    # 获取仓库信息
    local repo_info
    if repo_info=$(gh -R . repo view --json owner,name,url 2>/dev/null); then
        echo "$repo_info" | jq '. + {"supported": true}'
    else
        cat << EOF
{
    "supported": false,
    "owner": null,
    "name": null,
    "url": null,
    "error": "Failed to fetch repository information"
}
EOF
        return 1
    fi
}

# 检查GitHub CLI版本兼容性
# 参数：(min_version)
# 返回：0（兼容）或1（不兼容）
gh_check_version_compatibility() {
    local min_version="$1"
    
    if ! gh_check_installation; then
        return 1
    fi
    
    local current_version
    current_version=$(gh_get_version)
    
    if [[ -z "$current_version" ]]; then
        return 1
    fi
    
    # 简单版本比较（假设版本格式为 x.y.z）
    local current_major current_minor current_patch
    local min_major min_minor min_patch
    
    IFS='.' read -r current_major current_minor current_patch <<< "$current_version"
    IFS='.' read -r min_major min_minor min_patch <<< "$min_version"
    
    # 默认patch版本为0
    current_patch="${current_patch:-0}"
    min_patch="${min_patch:-0}"
    
    # 比较版本号
    if [[ "$current_major" -gt "$min_major" ]]; then
        return 0
    elif [[ "$current_major" -eq "$min_major" ]]; then
        if [[ "$current_minor" -gt "$min_minor" ]]; then
            return 0
        elif [[ "$current_minor" -eq "$min_minor" ]]; then
            if [[ "$current_patch" -ge "$min_patch" ]]; then
                return 0
            fi
        fi
    fi
    
    return 1
}

# 检查网络连接到GitHub
# 返回：0（可连接）或1（无法连接）
gh_check_connectivity() {
    if ! gh_check_installation; then
        return 1
    fi
    
    # 尝试访问GitHub API
    gh api --silent /user >/dev/null 2>&1
}

# 获取GitHub CLI完整状态
# 返回：JSON格式的状态信息
gh_get_status() {
    local installation_status="false"
    local auth_status="false"
    local connectivity_status="false"
    local version=""
    local user=""
    
    if gh_check_installation; then
        installation_status="true"
        version=$(gh_get_version)
        
        if gh_check_auth; then
            auth_status="true"
            user=$(gh_get_current_user)
            
            if gh_check_connectivity; then
                connectivity_status="true"
            fi
        fi
    fi
    
    cat << EOF
{
    "installed": $installation_status,
    "authenticated": $auth_status,
    "connected": $connectivity_status,
    "version": "$version",
    "user": "$user"
}
EOF
}

# 检查指定命令是否可用
# 参数：(command_name)
# 返回：0（可用）或1（不可用）
gh_check_command_available() {
    local command_name="$1"
    
    if ! gh_check_installation; then
        return 1
    fi
    
    # 检查命令是否在帮助列表中
    gh help 2>/dev/null | grep -q "^  $command_name" 2>/dev/null
}

# 获取GitHub CLI支持的命令列表
# 返回：命令列表，每行一个命令
gh_list_available_commands() {
    if ! gh_check_installation; then
        return 1
    fi
    
    gh help 2>/dev/null | awk '/^  [a-z]/ {print $1}' || true
}