#!/bin/bash
# GPF 状态检查模块 - 提供统一状态检查功能
# 本模块为 pr/clean/sync/status 命令提供完整的状态检查服务

set -euo pipefail

# 按四层架构获取项目根目录（通过composite层）
source "$(dirname "${BASH_SOURCE[0]}")/../composite/environment-composite.sh"

# 通过composite层获取项目根目录（遵循四层架构）
PROJECT_ROOT=$(environment_get_project_root) || {
    echo "❌ 错误：无法通过composite层获取项目根目录" >&2
    exit 1
}

# 加载依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/environment-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/git-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/github-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/worktree-composite.sh"

# ==============================================================================
# 统一状态检查模块 - 核心方法
# ==============================================================================

# 获取完整的分支状态信息（为所有命令提供统一接口）
status_module_get_complete_status() {
    local branch_name="$1"
    local target_branch="${2:-}"
    local purpose="${3:-general}"  # pr/clean/sync/status

    # 验证输入参数
    [[ -n "$branch_name" ]] || {
        echo "❌ 错误：分支名称不能为空" >&2
        return 1
    }

    # 获取分支环境信息
    local branch_info
    branch_info=$(status_module_analyze_branch_environment "$branch_name") || return 1
    
    local branch_type="${branch_info%%:*}"
    local worktree_path="${branch_info#*:}"
    
    # 获取基础状态
    local base_status
    base_status=$(status_module_get_base_status "$branch_name" "$worktree_path") || return 1
    
    # 获取目标分支关系状态
    local target_status=""
    if [[ -n "$target_branch" ]]; then
        target_status=$(status_module_get_target_relationship "$branch_name" "$target_branch" "$worktree_path") || return 1
    fi
    
    # 获取GitHub状态
    local github_status
    github_status=$(status_module_get_github_status "$branch_name" "$worktree_path") || return 1
    
    # 根据用途返回适当的状态信息
    case "$purpose" in
        "pr")
            status_module_format_pr_status "$branch_name" "$target_branch" "$base_status" "$target_status" "$github_status"
            ;;
        "clean")
            status_module_format_clean_status "$branch_name" "$base_status" "$target_status" "$github_status"
            ;;
        "sync")
            status_module_format_sync_status "$branch_name" "$target_branch" "$base_status" "$target_status"
            ;;
        "status"|"general")
            status_module_format_general_status "$branch_name" "$base_status" "$target_status" "$github_status"
            ;;
        *)
            echo "❌ 错误：未知的状态检查目的: $purpose" >&2
            return 1
            ;;
    esac
}

# 分析分支环境信息
status_module_analyze_branch_environment() {
    local branch_name="$1"
    
    # 确定分支类型和worktree路径
    local worktree_path
    if [[ "$branch_name" =~ ^epic-.*-e$ ]]; then
        # Epic分支
        worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
        echo "epic:$worktree_path"
    elif [[ "$branch_name" =~ ^epic-.*-e-.*-ef$ ]]; then
        # Feature分支
        worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
        echo "feature:$worktree_path"
    else
        # 其他分支（可能在根目录）
        echo "root:$PROJECT_ROOT"
    fi
}

# 获取基础状态（工作区、暂存区、分支推送状态）
status_module_get_base_status() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 检查路径是否存在
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 工作区状态
    local working_tree_clean="false"
    if check_working_tree_clean_remote "$worktree_path"; then
        working_tree_clean="true"
    fi
    
    # 暂存区状态
    local staging_area_clean="false"
    if check_staging_area_clean_remote "$worktree_path"; then
        staging_area_clean="true"
    fi
    
    # 分支推送状态
    local branch_pushed="false"
    if check_branch_pushed_remote "$branch_name" "$worktree_path"; then
        branch_pushed="true"
    fi
    
    # 返回JSON格式状态
    cat <<EOF
{
    "working_tree_clean": $working_tree_clean,
    "staging_area_clean": $staging_area_clean,
    "branch_pushed": $branch_pushed,
    "branch_exists": true
}
EOF
}

# 获取与目标分支的关系状态
status_module_get_target_relationship() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="$3"
    
    # 检查分支是否已合并
    local branch_merged="false"
    if check_branch_merged_remote "$branch_name" "$target_branch" "$worktree_path"; then
        branch_merged="true"
    fi
    
    # 检查是否需要同步
    local needs_sync="false"
    if check_sync_requirements_remote "$branch_name" "$target_branch" "$worktree_path"; then
        needs_sync="true"
    fi
    
    # 获取commit差异
    local commits_ahead="0"
    local commits_behind="0"
    if [[ -d "$worktree_path" ]]; then
        commits_ahead=$(git -C "$worktree_path" rev-list --count "origin/$target_branch..$branch_name" 2>/dev/null || echo "0")
        commits_behind=$(git -C "$worktree_path" rev-list --count "$branch_name..origin/$target_branch" 2>/dev/null || echo "0")
    fi
    
    # 返回JSON格式状态
    cat <<EOF
{
    "branch_merged": $branch_merged,
    "needs_sync": $needs_sync,
    "commits_ahead": $commits_ahead,
    "commits_behind": $commits_behind,
    "target_branch": "$target_branch"
}
EOF
}

# 获取GitHub状态
status_module_get_github_status() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 检查GitHub环境
    local gh_available="false"
    if gh_check_installation && gh_check_auth; then
        gh_available="true"
    fi
    
    # 获取PR状态（如果可用）
    local pr_exists="false"
    local pr_number=""
    local pr_state=""
    
    if [[ "$gh_available" == "true" ]]; then
        local pr_info
        if pr_info=$(github_pr_query_by_branch "$branch_name" "$worktree_path" 2>/dev/null); then
            pr_exists="true"
            pr_number=$(echo "$pr_info" | jq -r '.number // ""')
            pr_state=$(echo "$pr_info" | jq -r '.state // ""')
        fi
    fi
    
    # 返回JSON格式状态
    cat <<EOF
{
    "gh_available": $gh_available,
    "pr_exists": $pr_exists,
    "pr_number": "$pr_number",
    "pr_state": "$pr_state"
}
EOF
}

# 格式化PR状态输出
status_module_format_pr_status() {
    local branch_name="$1"
    local target_branch="$2"
    local base_status="$3"
    local target_status="$4"
    local github_status="$5"
    
    # 解析状态
    local working_clean=$(echo "$base_status" | jq -r '.working_tree_clean')
    local staging_clean=$(echo "$base_status" | jq -r '.staging_area_clean')
    local branch_pushed=$(echo "$base_status" | jq -r '.branch_pushed')
    local pr_exists=$(echo "$github_status" | jq -r '.pr_exists')
    
    # 判断PR准备状态
    local pr_ready="true"
    local blocking_issues=()
    
    if [[ "$working_clean" != "true" ]]; then
        pr_ready="false"
        blocking_issues+=("工作区有未保存的修改")
    fi
    
    if [[ "$staging_clean" != "true" ]]; then
        pr_ready="false"
        blocking_issues+=("暂存区有未提交的内容")
    fi
    
    if [[ "$branch_pushed" != "true" ]]; then
        pr_ready="false"
        blocking_issues+=("分支未推送到远程")
    fi
    
    if [[ "$pr_exists" == "true" ]]; then
        pr_ready="false"
        blocking_issues+=("PR已存在")
    fi
    
    # 返回PR状态
    cat <<EOF
{
    "purpose": "pr",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "pr_ready": $pr_ready,
    "blocking_issues": [$(printf '"%s",' "${blocking_issues[@]}" | sed 's/,$//')],
    "base_status": $base_status,
    "target_status": $target_status,
    "github_status": $github_status
}
EOF
}

# 格式化清理状态输出
status_module_format_clean_status() {
    local branch_name="$1"
    local base_status="$2"
    local target_status="$3"
    local github_status="$4"
    
    # 解析状态
    local working_clean=$(echo "$base_status" | jq -r '.working_tree_clean')
    local staging_clean=$(echo "$base_status" | jq -r '.staging_area_clean')
    local branch_merged=$(echo "$target_status" | jq -r '.branch_merged // false')
    local branch_pushed=$(echo "$base_status" | jq -r '.branch_pushed')
    
    # 判断清理安全级别
    local safety_level="unknown"
    local safety_color=""
    
    if [[ "$working_clean" == "true" && "$staging_clean" == "true" && "$branch_merged" == "true" ]]; then
        safety_level="safe"
        safety_color="🟢"
    elif [[ "$working_clean" == "true" && "$staging_clean" == "true" && "$branch_pushed" == "true" ]]; then
        safety_level="warning"
        safety_color="🟡"
    else
        safety_level="dangerous"
        safety_color="🔴"
    fi
    
    # 返回清理状态
    cat <<EOF
{
    "purpose": "clean",
    "branch_name": "$branch_name",
    "safety_level": "$safety_level",
    "safety_color": "$safety_color",
    "base_status": $base_status,
    "target_status": $target_status,
    "github_status": $github_status
}
EOF
}

# 格式化同步状态输出
status_module_format_sync_status() {
    local branch_name="$1"
    local target_branch="$2"
    local base_status="$3"
    local target_status="$4"
    
    # 解析状态
    local working_clean=$(echo "$base_status" | jq -r '.working_tree_clean')
    local staging_clean=$(echo "$base_status" | jq -r '.staging_area_clean')
    local needs_sync=$(echo "$target_status" | jq -r '.needs_sync // false')
    local commits_behind=$(echo "$target_status" | jq -r '.commits_behind // 0')
    
    # 判断同步准备状态
    local sync_ready="true"
    local blocking_issues=()
    
    if [[ "$working_clean" != "true" ]]; then
        sync_ready="false"
        blocking_issues+=("工作区有未保存的修改")
    fi
    
    if [[ "$staging_clean" != "true" ]]; then
        sync_ready="false"
        blocking_issues+=("暂存区有未提交的内容")
    fi
    
    if [[ "$needs_sync" != "true" ]]; then
        sync_ready="false"
        blocking_issues+=("不需要同步")
    fi
    
    # 返回同步状态
    cat <<EOF
{
    "purpose": "sync",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "sync_ready": $sync_ready,
    "needs_sync": $needs_sync,
    "commits_behind": $commits_behind,
    "blocking_issues": [$(printf '"%s",' "${blocking_issues[@]}" | sed 's/,$//')],
    "base_status": $base_status,
    "target_status": $target_status
}
EOF
}

# 格式化通用状态输出
status_module_format_general_status() {
    local branch_name="$1"
    local base_status="$2"
    local target_status="$3"
    local github_status="$4"
    
    # 返回完整状态
    cat <<EOF
{
    "purpose": "general",
    "branch_name": "$branch_name",
    "base_status": $base_status,
    "target_status": $target_status,
    "github_status": $github_status
}
EOF
}

# ==============================================================================
# 便捷状态检查方法
# ==============================================================================

# 检查分支是否可以安全PR
status_module_check_pr_ready() {
    local branch_name="$1"
    local target_branch="$2"
    
    local status_result
    status_result=$(status_module_get_complete_status "$branch_name" "$target_branch" "pr") || return 1
    
    local pr_ready=$(echo "$status_result" | jq -r '.pr_ready')
    [[ "$pr_ready" == "true" ]]
}

# 检查分支是否可以安全清理
status_module_check_clean_safe() {
    local branch_name="$1"
    local target_branch="${2:-}"
    
    local status_result
    status_result=$(status_module_get_complete_status "$branch_name" "$target_branch" "clean") || return 1
    
    local safety_level=$(echo "$status_result" | jq -r '.safety_level')
    [[ "$safety_level" == "safe" ]]
}

# 检查分支是否需要同步
status_module_check_sync_needed() {
    local branch_name="$1"
    local target_branch="$2"
    
    local status_result
    status_result=$(status_module_get_complete_status "$branch_name" "$target_branch" "sync") || return 1
    
    local needs_sync=$(echo "$status_result" | jq -r '.needs_sync')
    [[ "$needs_sync" == "true" ]]
}

# ==============================================================================
# 辅助状态检查方法（从composite层调用）
# ==============================================================================

# 远程检查工作区是否干净
check_working_tree_clean_remote() {
    local worktree_path="$1"
    [[ -d "$worktree_path" ]] || return 1
    git -C "$worktree_path" diff --quiet 2>/dev/null
}

# 远程检查暂存区是否干净
check_staging_area_clean_remote() {
    local worktree_path="$1"
    [[ -d "$worktree_path" ]] || return 1
    git -C "$worktree_path" diff --cached --quiet 2>/dev/null
}

# 远程检查分支是否已推送
check_branch_pushed_remote() {
    local branch_name="$1"
    local worktree_path="$2"
    [[ -d "$worktree_path" ]] || return 1
    git -C "$worktree_path" rev-parse "origin/$branch_name" >/dev/null 2>&1
}

# 远程检查分支是否已合并
check_branch_merged_remote() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="$3"
    [[ -d "$worktree_path" ]] || return 1
    
    local merge_base commit_count
    merge_base=$(git -C "$worktree_path" merge-base "$branch_name" "$target_branch" 2>/dev/null || echo "")
    [[ -n "$merge_base" ]] || return 1
    
    commit_count=$(git -C "$worktree_path" rev-list --count "$merge_base..$branch_name" 2>/dev/null || echo "1")
    [[ "$commit_count" -eq 0 ]]
}

# 远程检查同步要求
check_sync_requirements_remote() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="$3"
    [[ -d "$worktree_path" ]] || return 1
    
    local target_latest_commit source_base_commit
    target_latest_commit=$(git -C "$worktree_path" rev-parse "origin/$target_branch" 2>/dev/null || echo "")
    source_base_commit=$(git -C "$worktree_path" merge-base "$branch_name" "origin/$target_branch" 2>/dev/null || echo "")
    
    [[ -n "$target_latest_commit" && -n "$source_base_commit" ]] || return 1
    [[ "$target_latest_commit" != "$source_base_commit" ]]
}