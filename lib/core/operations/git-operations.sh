#!/bin/bash
# GPF Git操作层 - 纯Git命令执行，无业务逻辑
# 提供安全的Git操作原语，包含rollback机制和错误处理

set -euo pipefail

# ==============================================================================
# Git操作层 - 核心原语
# ==============================================================================

# Git分支创建操作
git_branch_create_operation() {
    local branch_name="$1"
    local base_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    local safety_mode="${4:-safe}"
    
    # 前置安全检查
    [[ -n "$branch_name" && -n "$base_branch" ]] || {
        echo "❌ 错误：分支名和基础分支不能为空" >&2
        return 1
    }
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查分支是否已存在
    if git -C "$worktree_path" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        if [[ "$safety_mode" == "force" ]]; then
            echo "⚠️ 警告：分支 $branch_name 已存在，强制模式将覆盖" >&2
            git -C "$worktree_path" branch -D "$branch_name" 2>/dev/null || true
        else
            echo "❌ 错误：分支 $branch_name 已存在" >&2
            return 1
        fi
    fi
    
    # 执行Git操作
    if git -C "$worktree_path" checkout -b "$branch_name" "$base_branch" >/dev/null 2>&1; then
        echo "✅ 成功创建分支: $branch_name (基于 $base_branch)"
        return 0
    else
        echo "❌ 创建分支失败: $branch_name" >&2
        return 1
    fi
}

# Git分支删除操作
git_branch_delete_operation() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    local force_delete="${3:-false}"
    
    # 前置安全检查
    [[ -n "$branch_name" ]] || {
        echo "❌ 错误：分支名不能为空" >&2
        return 1
    }
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查分支存在性
    if ! git -C "$worktree_path" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        echo "⚠️ 警告：分支 $branch_name 不存在，跳过删除"
        return 0
    fi
    
    # 安全检查：不能删除当前分支
    local current_branch
    current_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" == "$branch_name" ]]; then
        echo "❌ 错误：不能删除当前分支: $branch_name" >&2
        return 1
    fi
    
    # 创建rollback点（记录分支引用）
    local branch_sha
    branch_sha=$(git -C "$worktree_path" rev-parse "$branch_name" 2>/dev/null)
    
    # 执行删除操作
    local delete_flag="-d"
    [[ "$force_delete" == "true" ]] && delete_flag="-D"
    
    if git -C "$worktree_path" branch $delete_flag "$branch_name" >/dev/null 2>&1; then
        echo "✅ 成功删除分支: $branch_name"
        echo "🔄 Rollback信息: git checkout -b $branch_name $branch_sha" >&2
        return 0
    else
        echo "❌ 删除分支失败: $branch_name" >&2
        return 1
    fi
}

# Git分支推送操作
git_branch_push_operation() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    local set_upstream="${3:-true}"
    
    # 前置安全检查
    [[ -n "$branch_name" ]] || {
        echo "❌ 错误：分支名不能为空" >&2
        return 1
    }
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查分支存在性
    if ! git -C "$worktree_path" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        echo "❌ 错误：分支 $branch_name 不存在" >&2
        return 1
    fi
    
    # 检查远程仓库连接
    if ! git -C "$worktree_path" ls-remote origin >/dev/null 2>&1; then
        echo "❌ 错误：无法连接到远程仓库 origin" >&2
        return 1
    fi
    
    # 执行推送操作
    local push_args=()
    [[ "$set_upstream" == "true" ]] && push_args+=("-u")
    push_args+=("origin" "$branch_name")
    
    if git -C "$worktree_path" push "${push_args[@]}" >/dev/null 2>&1; then
        echo "✅ 成功推送分支: $branch_name"
        return 0
    else
        echo "❌ 推送分支失败: $branch_name" >&2
        return 1
    fi
}

# Git合并操作
git_merge_operation() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    local merge_strategy="${4:-no-edit}"
    
    # 前置安全检查
    [[ -n "$source_branch" && -n "$target_branch" ]] || {
        echo "❌ 错误：源分支和目标分支不能为空" >&2
        return 1
    }
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查工作区干净性
    if ! git -C "$worktree_path" diff --quiet 2>/dev/null || ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
        echo "❌ 错误：工作区不干净，无法合并" >&2
        return 1
    fi
    
    # 保存当前分支作为rollback点
    local original_branch
    original_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    local original_sha
    original_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)
    
    # 切换到目标分支
    if ! git -C "$worktree_path" checkout "$target_branch" >/dev/null 2>&1; then
        echo "❌ 错误：无法切换到目标分支: $target_branch" >&2
        return 1
    fi
    
    # 执行合并操作
    local merge_args=("--$merge_strategy")
    if git -C "$worktree_path" merge "${merge_args[@]}" "$source_branch" >/dev/null 2>&1; then
        echo "✅ 成功合并: $source_branch → $target_branch"
        echo "🔄 Rollback信息: git reset --hard $original_sha && git checkout $original_branch" >&2
        return 0
    else
        echo "❌ 合并失败，可能存在冲突" >&2
        # 尝试恢复到原始状态
        git -C "$worktree_path" merge --abort 2>/dev/null || true
        git -C "$worktree_path" checkout "$original_branch" >/dev/null 2>&1 || true
        return 1
    fi
}

# Git检出操作
git_checkout_operation() {
    local target_ref="$1"
    local worktree_path="${2:-$(pwd)}"
    local create_if_not_exists="${3:-false}"
    
    # 前置安全检查
    [[ -n "$target_ref" ]] || {
        echo "❌ 错误：目标引用不能为空" >&2
        return 1
    }
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查工作区干净性
    if ! git -C "$worktree_path" diff --quiet 2>/dev/null || ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
        echo "❌ 错误：工作区不干净，无法检出" >&2
        return 1
    fi
    
    # 保存当前状态作为rollback点
    local original_branch
    original_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    # 执行检出操作
    local checkout_args=()
    [[ "$create_if_not_exists" == "true" ]] && checkout_args+=("-b")
    checkout_args+=("$target_ref")
    
    if git -C "$worktree_path" checkout "${checkout_args[@]}" >/dev/null 2>&1; then
        echo "✅ 成功检出: $target_ref"
        echo "🔄 Rollback信息: git checkout $original_branch" >&2
        return 0
    else
        echo "❌ 检出失败: $target_ref" >&2
        return 1
    fi
}

# Git提交操作
git_commit_operation() {
    local commit_message="$1"
    local worktree_path="${2:-$(pwd)}"
    local add_all="${3:-false}"
    
    # 前置安全检查
    [[ -n "$commit_message" ]] || {
        echo "❌ 错误：提交消息不能为空" >&2
        return 1
    }
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 可选：添加所有修改文件
    if [[ "$add_all" == "true" ]]; then
        git -C "$worktree_path" add . 2>/dev/null || {
            echo "❌ 错误：添加文件到暂存区失败" >&2
            return 1
        }
    fi
    
    # 检查是否有内容可提交
    if git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
        echo "⚠️ 警告：没有暂存的修改，跳过提交"
        return 0
    fi
    
    # 保存rollback点
    local original_sha
    original_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)
    
    # 执行提交操作
    if git -C "$worktree_path" commit -m "$commit_message" >/dev/null 2>&1; then
        local new_sha
        new_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)
        echo "✅ 成功提交: $new_sha"
        echo "🔄 Rollback信息: git reset --hard $original_sha" >&2
        return 0
    else
        echo "❌ 提交失败" >&2
        return 1
    fi
}

# Git抓取操作
git_fetch_operation() {
    local remote_name="${1:-origin}"
    local worktree_path="${2:-$(pwd)}"
    
    # 前置安全检查
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查远程仓库连接
    if ! git -C "$worktree_path" ls-remote "$remote_name" >/dev/null 2>&1; then
        echo "❌ 错误：无法连接到远程仓库: $remote_name" >&2
        return 1
    fi
    
    # 执行抓取操作
    if git -C "$worktree_path" fetch "$remote_name" >/dev/null 2>&1; then
        echo "✅ 成功抓取远程更新: $remote_name"
        return 0
    else
        echo "❌ 抓取失败: $remote_name" >&2
        return 1
    fi
}

# Git拉取操作
git_pull_operation() {
    local remote_name="${1:-origin}"
    local branch_name="${2:-}"
    local worktree_path="${3:-$(pwd)}"
    
    # 前置安全检查
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树路径不存在: $worktree_path" >&2
        return 1
    }
    
    # 检查工作区干净性
    if ! git -C "$worktree_path" diff --quiet 2>/dev/null || ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
        echo "❌ 错误：工作区不干净，无法拉取" >&2
        return 1
    fi
    
    # 保存rollback点
    local original_sha
    original_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)
    
    # 构造拉取参数
    local pull_args=("$remote_name")
    [[ -n "$branch_name" ]] && pull_args+=("$branch_name")
    
    # 执行拉取操作
    if git -C "$worktree_path" pull "${pull_args[@]}" >/dev/null 2>&1; then
        echo "✅ 成功拉取更新: ${pull_args[*]}"
        echo "🔄 Rollback信息: git reset --hard $original_sha" >&2
        return 0
    else
        echo "❌ 拉取失败，可能存在冲突" >&2
        # 尝试恢复到原始状态
        git -C "$worktree_path" reset --hard "$original_sha" >/dev/null 2>&1 || true
        return 1
    fi
}

# ==============================================================================
# 辅助操作方法
# ==============================================================================

# 验证Git仓库状态
git_validate_repository() {
    local worktree_path="${1:-$(pwd)}"
    
    [[ -d "$worktree_path" ]] || {
        echo "❌ 路径不存在: $worktree_path" >&2
        return 1
    }
    
    if ! git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 不是有效的Git仓库: $worktree_path" >&2
        return 1
    fi
    
    return 0
}

# 检查工作区状态
git_check_workspace_clean() {
    local worktree_path="${1:-$(pwd)}"
    
    git_validate_repository "$worktree_path" || return 1
    
    # 检查未暂存修改
    if ! git -C "$worktree_path" diff --quiet 2>/dev/null; then
        return 1
    fi
    
    # 检查已暂存修改
    if ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# 获取当前分支名
git_get_current_branch() {
    local worktree_path="${1:-$(pwd)}"
    
    git_validate_repository "$worktree_path" || return 1
    
    git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || {
        echo "❌ 无法获取当前分支" >&2
        return 1
    }
}