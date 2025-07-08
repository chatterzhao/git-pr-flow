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

# 加载依赖 - 使用相对路径
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/environment-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/git-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/github-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/validation-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/worktree-composite.sh"

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
        "start")
            status_module_format_start_status "$branch_name" "$target_branch" "$base_status" "$target_status"
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
    
    # 通过Composite层获取Git状态
    local git_status
    git_status=$(git_get_complete_status "$branch_name" "$worktree_path") || {
        echo "❌ 错误：无法获取Git状态" >&2
        return 1
    }
    
    # 提取状态信息
    local working_tree_clean=$(echo "$git_status" | jq -r '.working_tree_clean')
    local staging_area_clean=$(echo "$git_status" | jq -r '.staging_area_clean')
    local branch_pushed=$(echo "$git_status" | jq -r '.branch_pushed')
    local remote_exists=$(echo "$git_status" | jq -r '.remote_exists')
    local ahead_count=$(echo "$git_status" | jq -r '.ahead_count // 0')
    local behind_count=$(echo "$git_status" | jq -r '.behind_count // 0')
    local has_merge_conflicts=$(echo "$git_status" | jq -r '.has_merge_conflicts // false')
    
    # 确定同步状态描述
    local sync_status_desc=""
    if [[ "$remote_exists" == "false" ]]; then
        sync_status_desc="远程无此分支"
    elif [[ "$branch_pushed" == "true" ]]; then
        sync_status_desc="已同步"
    elif [[ "$ahead_count" -gt 0 && "$behind_count" -gt 0 ]]; then
        sync_status_desc="本地领先${ahead_count}个提交，落后${behind_count}个提交"
    elif [[ "$ahead_count" -gt 0 ]]; then
        sync_status_desc="本地领先${ahead_count}个提交"
    elif [[ "$behind_count" -gt 0 ]]; then
        sync_status_desc="本地落后${behind_count}个提交"
    else
        sync_status_desc="未知状态"
    fi
    
    # 返回JSON格式状态
    cat <<EOF
{
    "working_tree_clean": $working_tree_clean,
    "staging_area_clean": $staging_area_clean,
    "branch_pushed": $branch_pushed,
    "remote_exists": $remote_exists,
    "ahead_count": $ahead_count,
    "behind_count": $behind_count,
    "sync_status_desc": "$sync_status_desc",
    "has_merge_conflicts": $has_merge_conflicts,
    "branch_exists": true
}
EOF
}

# 获取与目标分支的关系状态
status_module_get_target_relationship() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="$3"
    
    # 通过Composite层检查合并状态
    local merge_status
    merge_status=$(git_check_merge_status "$branch_name" "$target_branch" "$worktree_path") || {
        echo "❌ 错误：无法检查合并状态" >&2
        return 1
    }
    
    local branch_merged=$(echo "$merge_status" | jq -r '.is_merged')
    local commits_ahead=$(echo "$merge_status" | jq -r '.ahead_count // 0')
    local commits_behind=$(echo "$merge_status" | jq -r '.behind_count // 0')
    local needs_sync="false"
    
    if [[ "$commits_behind" -gt 0 ]]; then
        needs_sync="true"
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
    local blocking_issues_json=""
    if [[ ${#blocking_issues[@]} -gt 0 ]]; then
        blocking_issues_json=$(printf '"%s",' "${blocking_issues[@]}" | sed 's/,$//')
    fi
    
    cat <<EOF
{
    "purpose": "pr",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "pr_ready": $pr_ready,
    "blocking_issues": [$blocking_issues_json],
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
    local blocking_issues_json=""
    if [[ ${#blocking_issues[@]} -gt 0 ]]; then
        blocking_issues_json=$(printf '"%s",' "${blocking_issues[@]}" | sed 's/,$//')
    fi
    
    cat <<EOF
{
    "purpose": "sync",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "sync_ready": $sync_ready,
    "needs_sync": $needs_sync,
    "commits_behind": $commits_behind,
    "blocking_issues": [$blocking_issues_json],
    "base_status": $base_status,
    "target_status": $target_status
}
EOF
}

# 格式化开始命令状态输出
status_module_format_start_status() {
    local branch_name="$1"
    local target_branch="$2"
    local base_status="$3"
    local target_status="$4"
    
    # 解析状态
    local working_clean=$(echo "$base_status" | jq -r '.working_tree_clean')
    local staging_clean=$(echo "$base_status" | jq -r '.staging_area_clean')
    local has_conflicts=$(echo "$base_status" | jq -r '.has_merge_conflicts // false')
    local base_fresh=$(echo "$target_status" | jq -r '.base_branch_fresh // true')
    local commits_behind=$(echo "$target_status" | jq -r '.commits_behind // 0')
    
    # 判断开始操作的准备状态
    local start_ready="true"
    local blocking_issues=()
    local warnings=()
    
    # 检查阻断性问题
    if [[ "$has_conflicts" == "true" ]]; then
        start_ready="false"
        blocking_issues+=("存在未解决的合并冲突")
    fi
    
    # 检查警告性问题
    if [[ "$working_clean" != "true" ]]; then
        warnings+=("工作区有未保存的修改")
    fi
    
    if [[ "$staging_clean" != "true" ]]; then
        warnings+=("暂存区有未提交的内容")
    fi
    
    if [[ "$base_fresh" != "true" ]]; then
        warnings+=("基础分支不是最新版本，建议先同步")
    fi
    
    if [[ "$commits_behind" -gt 0 ]]; then
        warnings+=("分支落后基础分支 $commits_behind 个提交")
    fi
    
    # 返回start状态
    local blocking_issues_json=""
    if [[ ${#blocking_issues[@]} -gt 0 ]]; then
        blocking_issues_json=$(printf '"%s",' "${blocking_issues[@]}" | sed 's/,$//')
    fi
    
    local warnings_json=""
    if [[ ${#warnings[@]} -gt 0 ]]; then
        warnings_json=$(printf '"%s",' "${warnings[@]}" | sed 's/,$//')
    fi
    
    cat <<EOF
{
    "purpose": "start",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "start_ready": $start_ready,
    "base_fresh": $base_fresh,
    "commits_behind": $commits_behind,
    "blocking_issues": [$blocking_issues_json],
    "warnings": [$warnings_json],
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

