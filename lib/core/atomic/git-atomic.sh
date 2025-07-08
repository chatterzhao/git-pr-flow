#!/bin/bash
# GPF Core - Git Operations Atomic Methods
# Git操作原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 获取当前分支名
# 参数：(optional: worktree_path)
# 返回：当前分支名 或 返回码1（在detached HEAD）
git_get_current_branch() {
    local worktree_path="${1:-$(pwd)}"
    
    # 使用 Git 2.22+ 的 --show-current，如果不支持则回退到旧方法
    if git -C "$worktree_path" branch --show-current 2>/dev/null; then
        return 0
    else
        # 回退方法：解析 symbolic-ref
        local branch_ref
        branch_ref=$(git -C "$worktree_path" symbolic-ref HEAD 2>/dev/null) || return 1
        echo "${branch_ref#refs/heads/}"
    fi
}

# 检查工作区是否干净（无未暂存修改）
# 参数：(optional: worktree_path)
# 返回：0（干净）或1（有修改）
git_check_working_tree_clean() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" diff-files --quiet 2>/dev/null
}

# 检查暂存区是否干净（无已暂存修改）
# 参数：(optional: worktree_path)
# 返回：0（干净）或1（有修改）
git_check_staging_area_clean() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" diff-index --quiet --cached HEAD 2>/dev/null
}

# 检查是否有未跟踪文件
# 参数：(optional: worktree_path)
# 返回：0（无未跟踪文件）或1（有未跟踪文件）
git_check_no_untracked_files() {
    local worktree_path="${1:-$(pwd)}"
    
    local untracked_count
    untracked_count=$(git -C "$worktree_path" ls-files --others --exclude-standard | wc -l)
    [[ "$untracked_count" -eq 0 ]]
}

# 获取工作区修改的文件列表
# 参数：(optional: worktree_path)
# 返回：修改文件列表，每行一个文件
git_get_modified_files() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" diff-files --name-only 2>/dev/null || true
}

# 获取暂存区修改的文件列表
# 参数：(optional: worktree_path)
# 返回：暂存文件列表，每行一个文件
git_get_staged_files() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" diff-index --cached --name-only HEAD 2>/dev/null || true
}

# 获取未跟踪文件列表
# 参数：(optional: worktree_path)
# 返回：未跟踪文件列表，每行一个文件
git_get_untracked_files() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" ls-files --others --exclude-standard 2>/dev/null || true
}

# 检查分支是否存在于远程
# 参数：(branch_name, optional: worktree_path)
# 返回：0（存在）或1（不存在）
git_check_branch_exists_on_remote() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    local default_remote
    default_remote=$(git_get_default_remote "$worktree_path") || return 1
    
    git -C "$worktree_path" rev-parse "$default_remote/$branch_name" >/dev/null 2>&1
}

# 检查分支是否已推送（本地与远程同步）
# 参数：(branch_name, optional: worktree_path)
# 返回：0（已推送且同步）或1（未推送或不同步）
git_check_branch_pushed() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    local default_remote
    default_remote=$(git_get_default_remote "$worktree_path") || return 1
    
    # 首先检查远程分支是否存在
    if ! git_check_branch_exists_on_remote "$branch_name" "$worktree_path"; then
        return 1
    fi
    
    # 比较本地和远程的commit哈希
    local local_hash remote_hash
    local_hash=$(git -C "$worktree_path" rev-parse "$branch_name" 2>/dev/null) || return 1
    remote_hash=$(git -C "$worktree_path" rev-parse "$default_remote/$branch_name" 2>/dev/null) || return 1
    
    [[ "$local_hash" == "$remote_hash" ]]
}

# 检查本地分支是否领先于远程
# 参数：(branch_name, optional: worktree_path)
# 返回：0（领先）或1（不领先或同步）
git_check_branch_ahead_of_remote() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    local default_remote
    default_remote=$(git_get_default_remote "$worktree_path") || return 1
    
    # 检查远程分支是否存在
    if ! git_check_branch_exists_on_remote "$branch_name" "$worktree_path"; then
        # 远程不存在，本地肯定领先
        return 0
    fi
    
    # 检查是否有本地提交未推送到远程
    local ahead_count
    ahead_count=$(git -C "$worktree_path" rev-list --count "$default_remote/$branch_name..$branch_name" 2>/dev/null || echo "0")
    [[ "$ahead_count" -gt 0 ]]
}

# 检查本地分支是否落后于远程
# 参数：(branch_name, optional: worktree_path)
# 返回：0（落后）或1（不落后或同步）
git_check_branch_behind_remote() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    local default_remote
    default_remote=$(git_get_default_remote "$worktree_path") || return 1
    
    # 检查远程分支是否存在
    if ! git_check_branch_exists_on_remote "$branch_name" "$worktree_path"; then
        # 远程不存在，本地不可能落后
        return 1
    fi
    
    # 检查是否有远程提交未合并到本地
    local behind_count
    behind_count=$(git -C "$worktree_path" rev-list --count "$branch_name..$default_remote/$branch_name" 2>/dev/null || echo "0")
    [[ "$behind_count" -gt 0 ]]
}

# 检查分支是否已合并到目标分支
# 参数：(source_branch, target_branch, optional: worktree_path)
# 返回：0（已合并）或1（未合并）
git_check_branch_merged() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    # 检查source_branch的提交是否都在target_branch中
    local unmerged_commits
    unmerged_commits=$(git -C "$worktree_path" rev-list "$source_branch" ^"$target_branch" 2>/dev/null || true)
    
    [[ -z "$unmerged_commits" ]]
}

# 获取两个分支之间的提交数量
# 参数：(from_branch, to_branch, optional: worktree_path)
# 返回：提交数量
git_get_commit_count_between() {
    local from_branch="$1"
    local to_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    git -C "$worktree_path" rev-list --count "$from_branch..$to_branch" 2>/dev/null || echo "0"
}

# 检查Git仓库是否有效
# 参数：(optional: worktree_path)
# 返回：0（有效）或1（无效）
git_check_repository_valid() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1
}

# 获取最新的commit哈希
# 参数：(optional: branch_name, optional: worktree_path)
# 返回：commit哈希
git_get_latest_commit_hash() {
    local branch_name="${1:-HEAD}"
    local worktree_path="${2:-$(pwd)}"
    
    git -C "$worktree_path" rev-parse "$branch_name" 2>/dev/null || echo ""
}

# 检查是否在detached HEAD状态
# 参数：(optional: worktree_path)
# 返回：0（在detached HEAD）或1（在分支上）
git_check_detached_head() {
    local worktree_path="${1:-$(pwd)}"
    
    ! git -C "$worktree_path" symbolic-ref HEAD >/dev/null 2>&1
}

# 获取默认远程名称
# 参数：(optional: worktree_path)
# 返回：默认远程名称（优先级：origin > all > 第一个远程）
git_get_default_remote() {
    local worktree_path="${1:-$(pwd)}"
    
    # 获取所有远程
    local remotes
    remotes=$(git -C "$worktree_path" remote 2>/dev/null || echo "")
    
    if [[ -z "$remotes" ]]; then
        echo ""
        return 1
    fi
    
    # 优先使用 origin
    if echo "$remotes" | grep -q "^origin$"; then
        echo "origin"
        return 0
    fi
    
    # 其次使用 all
    if echo "$remotes" | grep -q "^all$"; then
        echo "all"
        return 0
    fi
    
    # 最后使用第一个远程
    echo "$remotes" | head -n1
}

# 获取未合并的冲突文件列表（纯Git命令）
# 参数：(optional: worktree_path)
# 返回：冲突文件列表，每行一个文件
git_ls_files_unmerged() {
    local worktree_path="${1:-$(pwd)}"
    
    git -C "$worktree_path" ls-files --unmerged 2>/dev/null | cut -f2 | sort -u
}