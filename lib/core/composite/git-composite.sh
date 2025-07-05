#!/bin/bash
# GPF Core - Git Operations Composite Methods
# Git操作组合方法 - 组合原子方法实现复杂逻辑

set -euo pipefail

# 导入依赖的原子方法
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/git-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/environment-atomic.sh"

# 验证分支状态的完整性
# 参数：(branch_name, optional: worktree_path)
# 返回：0（状态良好）或1（状态异常），状态信息输出到stdout
git_validate_branch_state() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 检查Git仓库是否有效
    if ! git_check_repository_valid "$worktree_path"; then
        echo "❌ 错误：无效的Git仓库路径：$worktree_path" >&2
        return 1
    fi
    
    # 检查当前分支是否匹配
    local current_branch
    current_branch=$(git_get_current_branch "$worktree_path") || {
        echo "❌ 错误：无法获取当前分支，可能处于detached HEAD状态" >&2
        return 1
    }
    
    if [[ "$current_branch" != "$branch_name" ]]; then
        echo "❌ 错误：当前分支 $current_branch 与期望分支 $branch_name 不匹配" >&2
        return 1
    fi
    
    # 检查工作区状态
    local working_tree_clean staging_area_clean has_untracked
    working_tree_clean=$(git_check_working_tree_clean "$worktree_path" && echo "true" || echo "false")
    staging_area_clean=$(git_check_staging_area_clean "$worktree_path" && echo "true" || echo "false")
    has_untracked=$(git_check_no_untracked_files "$worktree_path" && echo "false" || echo "true")
    
    # 检查远程状态
    local remote_exists ahead_count behind_count
    remote_exists=$(git_check_branch_exists_on_remote "$branch_name" "$worktree_path" && echo "true" || echo "false")
    
    if [[ "$remote_exists" == "true" ]]; then
        ahead_count=$(git_get_commit_count_between "origin/$branch_name" "$branch_name" "$worktree_path")
        behind_count=$(git_get_commit_count_between "$branch_name" "origin/$branch_name" "$worktree_path")
    else
        ahead_count="0"
        behind_count="0"
    fi
    
    # 输出状态信息
    cat << EOF
{
    "branch": "$branch_name",
    "current_branch": "$current_branch",
    "working_tree_clean": $working_tree_clean,
    "staging_area_clean": $staging_area_clean,
    "has_untracked": $has_untracked,
    "remote_exists": $remote_exists,
    "ahead_count": $ahead_count,
    "behind_count": $behind_count,
    "worktree_path": "$worktree_path"
}
EOF
    
    return 0
}

# 确保Git操作的安全状态
# 参数：(operation_type, optional: worktree_path)
# operation_type: "switch" | "merge" | "delete" | "push" | "pull"
# 返回：0（安全）或1（不安全）
git_ensure_safe_state() {
    local operation_type="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 获取当前分支
    local current_branch
    current_branch=$(git_get_current_branch "$worktree_path") || {
        echo "❌ 错误：无法获取当前分支" >&2
        return 1
    }
    
    # 获取分支状态
    local branch_state
    branch_state=$(git_validate_branch_state "$current_branch" "$worktree_path") || {
        return 1
    }
    
    # 提取状态信息
    local working_tree_clean staging_area_clean has_untracked
    working_tree_clean=$(echo "$branch_state" | grep -o '"working_tree_clean": [^,]*' | cut -d':' -f2 | tr -d ' ')
    staging_area_clean=$(echo "$branch_state" | grep -o '"staging_area_clean": [^,]*' | cut -d':' -f2 | tr -d ' ')
    has_untracked=$(echo "$branch_state" | grep -o '"has_untracked": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    # 根据操作类型检查安全性
    case "$operation_type" in
        "switch")
            if [[ "$working_tree_clean" != "true" ]]; then
                echo "❌ 错误：工作区有未保存的修改，无法切换分支" >&2
                git_get_modified_files "$worktree_path" | sed 's/^/  - /' >&2
                return 1
            fi
            if [[ "$staging_area_clean" != "true" ]]; then
                echo "❌ 错误：暂存区有未提交的修改，无法切换分支" >&2
                git_get_staged_files "$worktree_path" | sed 's/^/  - /' >&2
                return 1
            fi
            ;;
        "merge"|"pull")
            if [[ "$working_tree_clean" != "true" ]] || [[ "$staging_area_clean" != "true" ]]; then
                echo "❌ 错误：工作区或暂存区有未保存的修改，无法执行 $operation_type 操作" >&2
                return 1
            fi
            ;;
        "delete")
            if [[ "$working_tree_clean" != "true" ]] || [[ "$staging_area_clean" != "true" ]] || [[ "$has_untracked" == "true" ]]; then
                echo "❌ 错误：分支有未保存的修改或未跟踪文件，无法删除" >&2
                return 1
            fi
            ;;
        "push")
            if [[ "$staging_area_clean" != "true" ]]; then
                echo "❌ 错误：暂存区有未提交的修改，无法推送" >&2
                return 1
            fi
            ;;
        *)
            echo "❌ 错误：不支持的操作类型：$operation_type" >&2
            return 1
            ;;
    esac
    
    echo "✅ 安全检查通过：可以执行 $operation_type 操作"
    return 0
}

# 准备Git操作（拉取远程更新）
# 参数：(optional: worktree_path)
# 返回：0（成功）或1（失败）
git_prepare_for_operation() {
    local worktree_path="${1:-$(pwd)}"
    
    # 确保工作区干净
    if ! git_ensure_safe_state "pull" "$worktree_path"; then
        return 1
    fi
    
    # 获取当前分支
    local current_branch
    current_branch=$(git_get_current_branch "$worktree_path") || {
        echo "❌ 错误：无法获取当前分支" >&2
        return 1
    }
    
    # 拉取远程更新
    echo "📥 拉取远程更新..."
    if ! git -C "$worktree_path" fetch --quiet 2>/dev/null; then
        echo "⚠️ 警告：无法拉取远程更新，可能是网络问题" >&2
    fi
    
    # 检查是否有远程更新
    if git_check_branch_exists_on_remote "$current_branch" "$worktree_path"; then
        if git_check_branch_behind_remote "$current_branch" "$worktree_path"; then
            echo "📥 发现远程更新，正在合并..."
            if ! git -C "$worktree_path" merge --quiet "origin/$current_branch"; then
                echo "❌ 错误：合并远程更新失败" >&2
                return 1
            fi
            echo "✅ 远程更新合并完成"
        else
            echo "✅ 分支已是最新状态"
        fi
    else
        echo "ℹ️ 远程分支不存在，将在推送时创建"
    fi
    
    return 0
}

# 智能分支切换
# 参数：(target_branch, optional: worktree_path)
# 返回：0（成功）或1（失败）
git_intelligent_branch_switch() {
    local target_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 获取当前分支
    local current_branch
    current_branch=$(git_get_current_branch "$worktree_path") || {
        echo "❌ 错误：无法获取当前分支" >&2
        return 1
    }
    
    # 如果已经在目标分支，直接返回
    if [[ "$current_branch" == "$target_branch" ]]; then
        echo "✅ 已在目标分支：$target_branch"
        return 0
    fi
    
    # 检查切换安全性
    if ! git_ensure_safe_state "switch" "$worktree_path"; then
        return 1
    fi
    
    # 检查目标分支是否存在
    if git -C "$worktree_path" rev-parse --verify "$target_branch" >/dev/null 2>&1; then
        # 分支存在，直接切换
        echo "🔄 切换到现有分支：$target_branch"
        if ! git -C "$worktree_path" checkout "$target_branch" 2>/dev/null; then
            echo "❌ 错误：切换分支失败" >&2
            return 1
        fi
    else
        # 分支不存在，创建新分支
        echo "🆕 创建新分支：$target_branch"
        if ! git -C "$worktree_path" checkout -b "$target_branch" 2>/dev/null; then
            echo "❌ 错误：创建分支失败" >&2
            return 1
        fi
    fi
    
    echo "✅ 成功切换到分支：$target_branch"
    return 0
}

# 检查分支合并状态
# 参数：(source_branch, target_branch, optional: worktree_path)
# 返回：0（可合并）或1（不可合并），合并状态信息输出到stdout
git_check_merge_status() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    # 检查分支是否存在
    if ! git -C "$worktree_path" rev-parse --verify "$source_branch" >/dev/null 2>&1; then
        echo "❌ 错误：源分支 $source_branch 不存在" >&2
        return 1
    fi
    
    if ! git -C "$worktree_path" rev-parse --verify "$target_branch" >/dev/null 2>&1; then
        echo "❌ 错误：目标分支 $target_branch 不存在" >&2
        return 1
    fi
    
    # 检查是否已经合并
    local is_merged
    is_merged=$(git_check_branch_merged "$source_branch" "$target_branch" "$worktree_path" && echo "true" || echo "false")
    
    # 计算提交差异
    local ahead_count behind_count
    ahead_count=$(git_get_commit_count_between "$target_branch" "$source_branch" "$worktree_path")
    behind_count=$(git_get_commit_count_between "$source_branch" "$target_branch" "$worktree_path")
    
    # 检查是否有冲突
    local has_conflicts="false"
    if [[ "$is_merged" == "false" && "$ahead_count" -gt 0 ]]; then
        # 尝试合并检查（dry-run）
        if ! git -C "$worktree_path" merge-tree "$(git -C "$worktree_path" merge-base "$source_branch" "$target_branch")" "$source_branch" "$target_branch" | grep -q "^<<<<<"; then
            has_conflicts="true"
        fi
    fi
    
    # 输出合并状态信息
    cat << EOF
{
    "source_branch": "$source_branch",
    "target_branch": "$target_branch",
    "is_merged": $is_merged,
    "ahead_count": $ahead_count,
    "behind_count": $behind_count,
    "has_conflicts": $has_conflicts,
    "can_merge": $(if [[ "$is_merged" == "false" && "$ahead_count" -gt 0 && "$has_conflicts" == "false" ]]; then echo "true"; else echo "false"; fi)
}
EOF
    
    return 0
}

# 安全的分支删除检查
# 参数：(branch_name, optional: worktree_path)
# 返回：0（可安全删除）或1（不可删除）
git_check_safe_branch_deletion() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 检查分支是否存在
    if ! git -C "$worktree_path" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        echo "❌ 错误：分支 $branch_name 不存在" >&2
        return 1
    fi
    
    # 检查是否是当前分支
    local current_branch
    current_branch=$(git_get_current_branch "$worktree_path") || {
        echo "❌ 错误：无法获取当前分支" >&2
        return 1
    }
    
    if [[ "$current_branch" == "$branch_name" ]]; then
        echo "❌ 错误：不能删除当前分支：$branch_name" >&2
        return 1
    fi
    
    # 检查分支是否已合并到主分支
    local main_branches=("main" "master" "develop")
    local is_merged_to_main="false"
    
    for main_branch in "${main_branches[@]}"; do
        if git -C "$worktree_path" rev-parse --verify "$main_branch" >/dev/null 2>&1; then
            if git_check_branch_merged "$branch_name" "$main_branch" "$worktree_path"; then
                is_merged_to_main="true"
                echo "✅ 分支 $branch_name 已合并到 $main_branch"
                break
            fi
        fi
    done
    
    if [[ "$is_merged_to_main" == "false" ]]; then
        echo "⚠️ 警告：分支 $branch_name 未合并到主分支，删除将丢失提交" >&2
        return 1
    fi
    
    echo "✅ 分支 $branch_name 可以安全删除"
    return 0
}