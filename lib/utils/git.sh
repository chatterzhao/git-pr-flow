#!/usr/bin/env bash

# Git PR Flow - Git工具函数
# 提供Git操作的封装函数，包括分支管理、worktree操作等

# 检查Git环境
git_check_environment() {
    # 检查是否在Git仓库中
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        return 1
    fi
    
    # 检查Git版本
    local git_version
    git_version=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local required_version="2.20.0"
    
    if ! version_compare "$git_version" "$required_version"; then
        ui_error "Git版本过低，需要 $required_version 或更高版本，当前版本: $git_version"
        return 1
    fi
    
    return 0
}

# 版本比较函数
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # 简单的版本比较（假设格式为 x.y.z）
    local IFS='.'
    read -ra ver1 <<< "$version1"
    read -ra ver2 <<< "$version2"
    
    for i in {0..2}; do
        local v1="${ver1[$i]:-0}"
        local v2="${ver2[$i]:-0}"
        
        if ((v1 > v2)); then
            return 0
        elif ((v1 < v2)); then
            return 1
        fi
    done
    
    return 0  # 版本相等
}

# 获取当前分支名
git_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# 检查分支是否存在
git_branch_exists() {
    local branch_name="$1"
    git show-ref --verify --quiet "refs/heads/$branch_name"
}

# 检查远程分支是否存在
git_remote_branch_exists() {
    local branch_name="$1"
    local remote="${2:-origin}"
    git show-ref --verify --quiet "refs/remotes/$remote/$branch_name"
}

# 获取所有本地分支
git_list_branches() {
    git branch --format='%(refname:short)' | grep -v '^HEAD$' || true
}

# 获取所有Epic分支（包含/的分支）
git_list_epic_branches() {
    git branch --format='%(refname:short)' | grep '/' || true
}

# 检查工作目录是否干净
git_is_clean() {
    git diff --quiet && git diff --cached --quiet
}

# 检查是否有未跟踪的文件
git_has_untracked() {
    [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

# 获取工作目录状态摘要
git_status_summary() {
    local modified staged untracked
    
    modified=$(git diff --name-only | wc -l | tr -d ' ')
    staged=$(git diff --cached --name-only | wc -l | tr -d ' ')
    untracked=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')
    
    echo "修改:$modified 暂存:$staged 未跟踪:$untracked"
}

# 创建新分支
git_create_branch() {
    local branch_name="$1"
    local base_branch="${2:-HEAD}"
    
    if git_branch_exists "$branch_name"; then
        ui_error "分支 '$branch_name' 已存在"
        return 1
    fi
    
    if ! git checkout -b "$branch_name" "$base_branch" >/dev/null 2>&1; then
        ui_error "创建分支 '$branch_name' 失败"
        return 1
    fi
    
    ui_success "创建分支: $branch_name"
    return 0
}

# 切换分支
git_checkout_branch() {
    local branch_name="$1"
    
    if ! git_branch_exists "$branch_name"; then
        ui_error "分支 '$branch_name' 不存在"
        return 1
    fi
    
    if ! git checkout "$branch_name" >/dev/null 2>&1; then
        ui_error "切换到分支 '$branch_name' 失败"
        return 1
    fi
    
    ui_success "切换到分支: $branch_name"
    return 0
}

# 安全切换分支（检查工作目录状态）
git_safe_checkout() {
    local branch_name="$1"
    local force="${2:-false}"
    
    if [[ "$force" != "true" ]] && ! git_is_clean; then
        ui_error "工作目录不干净，请先提交或暂存更改"
        ui_info "当前状态: $(git_status_summary)"
        return 1
    fi
    
    git_checkout_branch "$branch_name"
}

# 检查分支是否被worktree使用
git_branch_in_worktree() {
    local branch_name="$1"
    
    # 获取所有worktree的分支信息
    git worktree list --porcelain | grep -q "branch refs/heads/$branch_name"
}

# 自动分支切换（核心功能）
git_auto_switch_branch() {
    local target_branch="$1"
    local current_branch
    current_branch=$(git_current_branch)
    
    log_debug "尝试自动切换分支: $current_branch -> $target_branch"
    
    # 如果已经在目标分支，无需切换
    if [[ "$current_branch" == "$target_branch" ]]; then
        ui_info "已在目标分支: $target_branch"
        return 0
    fi
    
    # 检查目标分支是否存在
    if ! git_branch_exists "$target_branch"; then
        ui_warning "目标分支 '$target_branch' 不存在，保持在当前分支"
        return 1
    fi
    
    # 检查目标分支是否被其他worktree使用
    if git_branch_in_worktree "$target_branch"; then
        ui_warning "分支 '$target_branch' 正被其他worktree使用，无法切换"
        return 1
    fi
    
    # 检查工作目录状态
    if ! git_is_clean; then
        ui_warning "工作目录不干净，跳过自动分支切换"
        ui_info "当前状态: $(git_status_summary)"
        return 1
    fi
    
    # 执行切换
    if git_safe_checkout "$target_branch" true; then
        ui_success "🔄 自动切换到分支: $target_branch"
        ui_info "VS Code现在可以显示 '$target_branch' 的文件变更"
        return 0
    else
        ui_error "自动分支切换失败"
        return 1
    fi
}

# Worktree操作函数

# 检查worktree是否存在
git_worktree_exists() {
    local worktree_path="$1"
    git worktree list | grep -q "$worktree_path"
}

# 创建worktree
git_create_worktree() {
    local worktree_path="$1"
    local branch_name="$2"
    local base_branch="${3:-HEAD}"
    
    if git_worktree_exists "$worktree_path"; then
        ui_error "Worktree '$worktree_path' 已存在"
        return 1
    fi
    
    # 创建目录
    ensure_dir "$(dirname "$worktree_path")"
    
    # 创建worktree和分支
    if git_branch_exists "$branch_name"; then
        # 分支已存在，直接checkout
        if ! git worktree add "$worktree_path" "$branch_name" >/dev/null 2>&1; then
            ui_error "创建worktree失败: $worktree_path"
            return 1
        fi
    else
        # 创建新分支和worktree
        if ! git worktree add -b "$branch_name" "$worktree_path" "$base_branch" >/dev/null 2>&1; then
            ui_error "创建worktree和分支失败: $worktree_path ($branch_name)"
            return 1
        fi
    fi
    
    ui_success "创建worktree: $worktree_path ($branch_name)"
    return 0
}

# 删除worktree
git_remove_worktree() {
    local worktree_path="$1"
    local force="${2:-false}"
    
    if ! git_worktree_exists "$worktree_path"; then
        ui_warning "Worktree '$worktree_path' 不存在"
        return 1
    fi
    
    local force_flag=""
    if [[ "$force" == "true" ]]; then
        force_flag="--force"
    fi
    
    if git worktree remove $force_flag "$worktree_path" >/dev/null 2>&1; then
        ui_success "删除worktree: $worktree_path"
        return 0
    else
        ui_error "删除worktree失败: $worktree_path"
        return 1
    fi
}

# 列出所有worktree
git_list_worktrees() {
    git worktree list --porcelain
}

# 获取worktree的分支信息
git_worktree_branch() {
    local worktree_path="$1"
    git worktree list --porcelain | awk -v path="$worktree_path" '
        $1 == "worktree" && $2 == path { found=1; next }
        found && $1 == "branch" { gsub(/^refs\/heads\//, "", $2); print $2; exit }
        $1 == "worktree" { found=0 }
    '
}

# 同步操作函数

# 检查分支是否落后于上游
git_behind_upstream() {
    local branch="${1:-$(git_current_branch)}"
    local upstream
    
    upstream=$(git config "branch.$branch.merge" 2>/dev/null) || return 1
    
    local behind
    behind=$(git rev-list --count HEAD.."$upstream" 2>/dev/null) || return 1
    
    [[ "$behind" -gt 0 ]]
}

# 检查分支是否领先于上游
git_ahead_upstream() {
    local branch="${1:-$(git_current_branch)}"
    local upstream
    
    upstream=$(git config "branch.$branch.merge" 2>/dev/null) || return 1
    
    local ahead
    ahead=$(git rev-list --count "$upstream"..HEAD 2>/dev/null) || return 1
    
    [[ "$ahead" -gt 0 ]]
}

# 获取分支的上游信息
git_upstream_info() {
    local branch="${1:-$(git_current_branch)}"
    
    local upstream_branch ahead behind
    upstream_branch=$(git config "branch.$branch.merge" 2>/dev/null | sed 's|refs/heads/||')
    
    if [[ -n "$upstream_branch" ]]; then
        ahead=$(git rev-list --count "$upstream_branch"..HEAD 2>/dev/null || echo "0")
        behind=$(git rev-list --count HEAD.."$upstream_branch" 2>/dev/null || echo "0")
        
        echo "upstream:$upstream_branch ahead:$ahead behind:$behind"
    else
        echo "upstream: ahead:0 behind:0"
    fi
}