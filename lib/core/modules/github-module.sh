#!/bin/bash
# GPF GitHub集成模块 - 提供完整的GitHub PR生命周期管理
# 本模块为命令层提供GitHub相关的高级业务功能

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/github-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/git-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"

# ==============================================================================
# GitHub PR生命周期管理模块
# ==============================================================================

# 创建PR的完整流程（pr命令的核心方法）
github_module_create_pr() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    local pr_options="${4:-}"  # JSON格式的PR选项
    
    # 验证输入参数
    [[ -n "$source_branch" && -n "$target_branch" ]] || {
        echo "❌ 错误：源分支和目标分支不能为空" >&2
        return 1
    }
    
    # 验证GitHub环境
    if ! github_module_validate_environment "$worktree_path"; then
        echo "❌ 错误：GitHub环境验证失败" >&2
        return 1
    fi
    
    # 检查PR是否已存在
    if github_module_check_pr_exists "$source_branch" "$worktree_path"; then
        echo "❌ 错误：PR已存在" >&2
        return 1
    fi
    
    # 确保分支已推送
    if ! github_module_ensure_branch_pushed "$source_branch" "$worktree_path"; then
        echo "❌ 错误：分支推送失败" >&2
        return 1
    fi
    
    # 生成PR信息
    local pr_info
    pr_info=$(github_module_generate_pr_info "$source_branch" "$target_branch" "$worktree_path" "$pr_options") || return 1
    
    # 创建PR
    local pr_result
    pr_result=$(github_module_execute_pr_creation "$pr_info" "$worktree_path") || return 1
    
    # 返回创建结果
    echo "$pr_result"
}

# 查询PR状态（status命令使用）
github_module_query_pr_status() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 验证GitHub环境
    if ! github_module_validate_environment "$worktree_path"; then
        echo '{"available": false, "reason": "GitHub环境不可用"}' 
        return 0
    fi
    
    # 查询PR信息
    local pr_info
    if pr_info=$(github_pr_query_by_branch "$branch_name" "$worktree_path" 2>/dev/null); then
        # PR存在，返回详细信息
        local pr_number=$(echo "$pr_info" | jq -r '.number')
        local pr_state=$(echo "$pr_info" | jq -r '.state')
        local pr_url=$(echo "$pr_info" | jq -r '.html_url')
        local pr_title=$(echo "$pr_info" | jq -r '.title')
        
        cat <<EOF
{
    "available": true,
    "pr_exists": true,
    "pr_number": $pr_number,
    "pr_state": "$pr_state",
    "pr_url": "$pr_url",
    "pr_title": "$pr_title"
}
EOF
    else
        # PR不存在
        cat <<EOF
{
    "available": true,
    "pr_exists": false,
    "pr_number": null,
    "pr_state": null,
    "pr_url": null,
    "pr_title": null
}
EOF
    fi
}

# 管理PR状态（合并、关闭等）
github_module_manage_pr() {
    local action="$1"          # merge/close/reopen/ready
    local branch_name="$2"
    local worktree_path="$3"
    local options="${4:-}"     # JSON格式的选项
    
    # 验证GitHub环境
    if ! github_module_validate_environment "$worktree_path"; then
        echo "❌ 错误：GitHub环境验证失败" >&2
        return 1
    fi
    
    # 获取PR信息
    local pr_info
    pr_info=$(github_pr_query_by_branch "$branch_name" "$worktree_path") || {
        echo "❌ 错误：未找到PR" >&2
        return 1
    }
    
    local pr_number=$(echo "$pr_info" | jq -r '.number')
    
    # 根据动作执行相应操作
    case "$action" in
        "merge")
            github_module_merge_pr "$pr_number" "$worktree_path" "$options"
            ;;
        "close")
            github_module_close_pr "$pr_number" "$worktree_path"
            ;;
        "reopen")
            github_module_reopen_pr "$pr_number" "$worktree_path"
            ;;
        "ready")
            github_module_mark_pr_ready "$pr_number" "$worktree_path"
            ;;
        *)
            echo "❌ 错误：未知的PR管理动作: $action" >&2
            return 1
            ;;
    esac
}

# 批量查询PR状态（clean命令使用）
github_module_batch_query_pr_status() {
    local branch_list="$1"    # 以空格分隔的分支列表
    local worktree_base="$2"  # worktree基础路径
    
    # 验证GitHub环境
    if ! gh_check_installation || ! gh_check_auth; then
        echo '{"available": false, "branches": []}' 
        return 0
    fi
    
    local results="[]"
    
    # 遍历分支列表
    for branch in $branch_list; do
        local worktree_path="$worktree_base/$branch"
        [[ -d "$worktree_path" ]] || continue
        
        local pr_status
        pr_status=$(github_module_query_pr_status "$branch" "$worktree_path")
        
        # 添加到结果中
        results=$(echo "$results" | jq --argjson pr_status "$pr_status" --arg branch "$branch" '. += [{branch: $branch, status: $pr_status}]')
    done
    
    cat <<EOF
{
    "available": true,
    "branches": $results
}
EOF
}

# ==============================================================================
# GitHub环境管理
# ==============================================================================

# 验证GitHub环境
github_module_validate_environment() {
    local worktree_path="$1"
    
    # 检查GitHub CLI
    if ! gh_check_installation; then
        echo "❌ GitHub CLI未安装" >&2
        return 1
    fi
    
    # 检查认证状态
    if ! gh_check_auth; then
        echo "❌ GitHub CLI未认证" >&2
        return 1
    fi
    
    # 检查网络连接
    if ! gh_check_connectivity; then
        echo "❌ GitHub网络连接失败" >&2
        return 1
    fi
    
    # 检查仓库配置
    if ! github_module_validate_repository "$worktree_path"; then
        echo "❌ 仓库配置验证失败" >&2
        return 1
    fi
    
    return 0
}

# 验证仓库配置
github_module_validate_repository() {
    local worktree_path="$1"
    
    # 检查是否为git仓库
    if ! git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 不是有效的Git仓库" >&2
        return 1
    fi
    
    # 检查远程仓库
    if ! git -C "$worktree_path" remote get-url origin >/dev/null 2>&1; then
        echo "❌ 未配置origin远程仓库" >&2
        return 1
    fi
    
    # 检查是否为GitHub仓库
    local origin_url
    origin_url=$(git -C "$worktree_path" remote get-url origin 2>/dev/null || echo "")
    if [[ ! "$origin_url" =~ github\.com ]]; then
        echo "❌ 不是GitHub仓库" >&2
        return 1
    fi
    
    return 0
}

# 获取GitHub仓库信息
github_module_get_repository_info() {
    local worktree_path="$1"
    
    # 获取仓库URL
    local origin_url
    origin_url=$(git -C "$worktree_path" remote get-url origin 2>/dev/null || echo "")
    
    # 解析仓库owner和name
    local repo_owner repo_name
    if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        repo_owner="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"
        repo_name="${repo_name%.git}"  # 移除.git后缀
    else
        echo "❌ 错误：无法解析GitHub仓库信息" >&2
        return 1
    fi
    
    # 返回仓库信息
    cat <<EOF
{
    "origin_url": "$origin_url",
    "repo_owner": "$repo_owner",
    "repo_name": "$repo_name",
    "repo_full_name": "$repo_owner/$repo_name"
}
EOF
}

# ==============================================================================
# PR创建和管理的具体实现
# ==============================================================================

# 检查PR是否已存在
github_module_check_pr_exists() {
    local branch_name="$1"
    local worktree_path="$2"
    
    local pr_info
    pr_info=$(github_pr_query_by_branch "$branch_name" "$worktree_path" 2>/dev/null)
    return $?
}

# 确保分支已推送
github_module_ensure_branch_pushed() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 检查分支是否已推送
    if git -C "$worktree_path" rev-parse "origin/$branch_name" >/dev/null 2>&1; then
        return 0
    fi
    
    # 推送分支
    if git -C "$worktree_path" push -u origin "$branch_name"; then
        echo "✅ 分支已推送到远程" >&2
        return 0
    else
        echo "❌ 分支推送失败" >&2
        return 1
    fi
}

# 生成PR信息
github_module_generate_pr_info() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    local pr_options="${4:-}"
    
    # 生成默认PR标题
    local pr_title
    pr_title=$(github_module_generate_pr_title "$source_branch" "$target_branch")
    
    # 生成默认PR描述
    local pr_body
    pr_body=$(github_module_generate_pr_body "$source_branch" "$target_branch" "$worktree_path")
    
    # 处理用户选项
    if [[ -n "$pr_options" ]]; then
        local custom_title=$(echo "$pr_options" | jq -r '.title // empty')
        local custom_body=$(echo "$pr_options" | jq -r '.body // empty')
        
        [[ -n "$custom_title" ]] && pr_title="$custom_title"
        [[ -n "$custom_body" ]] && pr_body="$custom_body"
    fi
    
    # 返回PR信息
    cat <<EOF
{
    "source_branch": "$source_branch",
    "target_branch": "$target_branch",
    "title": "$pr_title",
    "body": "$pr_body"
}
EOF
}

# 生成PR标题
github_module_generate_pr_title() {
    local source_branch="$1"
    local target_branch="$2"
    
    # 提取分支类型和名称
    if [[ "$source_branch" =~ ^epic-(.+)-e-(.+)-ef$ ]]; then
        # Feature分支
        local epic_name="${BASH_REMATCH[1]}"
        local feature_name="${BASH_REMATCH[2]}"
        echo "feat($epic_name): $feature_name"
    elif [[ "$source_branch" =~ ^epic-(.+)-e$ ]]; then
        # Epic分支
        local epic_name="${BASH_REMATCH[1]}"
        echo "epic: $epic_name"
    else
        # 其他分支
        echo "$source_branch → $target_branch"
    fi
}

# 生成PR描述
github_module_generate_pr_body() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    
    # 获取commit信息
    local commit_count
    commit_count=$(git -C "$worktree_path" rev-list --count "origin/$target_branch..$source_branch" 2>/dev/null || echo "0")
    
    # 生成基础描述
    cat <<EOF
## 变更概述
- 源分支: \`$source_branch\`
- 目标分支: \`$target_branch\`
- 提交数量: $commit_count

## 变更列表
$(git -C "$worktree_path" log --oneline "origin/$target_branch..$source_branch" 2>/dev/null || echo "无法获取commit历史")

## 测试
- [ ] 本地测试通过
- [ ] 代码审查完成

---
*此PR由GPF自动生成*
EOF
}

# 执行PR创建
github_module_execute_pr_creation() {
    local pr_info="$1"
    local worktree_path="$2"
    
    # 解析PR信息
    local source_branch=$(echo "$pr_info" | jq -r '.source_branch')
    local target_branch=$(echo "$pr_info" | jq -r '.target_branch')
    local pr_title=$(echo "$pr_info" | jq -r '.title')
    local pr_body=$(echo "$pr_info" | jq -r '.body')
    
    # 使用GitHub CLI创建PR
    local pr_result
    if pr_result=$(gh pr create \
        --base "$target_branch" \
        --head "$source_branch" \
        --title "$pr_title" \
        --body "$pr_body" \
        --repo "$(git -C "$worktree_path" remote get-url origin)" \
        2>&1); then
        
        # 提取PR URL
        local pr_url=$(echo "$pr_result" | grep -o 'https://github.com/[^/]*/[^/]*/pull/[0-9]*' | head -1)
        
        cat <<EOF
{
    "success": true,
    "pr_url": "$pr_url",
    "message": "PR创建成功"
}
EOF
    else
        cat <<EOF
{
    "success": false,
    "pr_url": null,
    "message": "PR创建失败: $pr_result"
}
EOF
        return 1
    fi
}

# 合并PR
github_module_merge_pr() {
    local pr_number="$1"
    local worktree_path="$2"
    local options="${3:-}"
    
    # 解析合并选项
    local merge_method="merge"  # 默认合并方式
    if [[ -n "$options" ]]; then
        merge_method=$(echo "$options" | jq -r '.merge_method // "merge"')
    fi
    
    # 执行合并
    if gh pr merge "$pr_number" --"$merge_method" --repo "$(git -C "$worktree_path" remote get-url origin)"; then
        echo "✅ PR #$pr_number 合并成功"
        return 0
    else
        echo "❌ PR #$pr_number 合并失败"
        return 1
    fi
}

# 关闭PR
github_module_close_pr() {
    local pr_number="$1"
    local worktree_path="$2"
    
    if gh pr close "$pr_number" --repo "$(git -C "$worktree_path" remote get-url origin)"; then
        echo "✅ PR #$pr_number 已关闭"
        return 0
    else
        echo "❌ PR #$pr_number 关闭失败"
        return 1
    fi
}

# 重新打开PR
github_module_reopen_pr() {
    local pr_number="$1"
    local worktree_path="$2"
    
    if gh pr reopen "$pr_number" --repo "$(git -C "$worktree_path" remote get-url origin)"; then
        echo "✅ PR #$pr_number 已重新打开"
        return 0
    else
        echo "❌ PR #$pr_number 重新打开失败"
        return 1
    fi
}

# 标记PR为ready
github_module_mark_pr_ready() {
    local pr_number="$1"
    local worktree_path="$2"
    
    if gh pr ready "$pr_number" --repo "$(git -C "$worktree_path" remote get-url origin)"; then
        echo "✅ PR #$pr_number 已标记为ready"
        return 0
    else
        echo "❌ PR #$pr_number 标记ready失败"
        return 1
    fi
}