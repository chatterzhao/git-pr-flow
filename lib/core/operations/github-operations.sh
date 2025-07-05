#!/bin/bash
# GPF GitHub操作层 - 简化版，纯GitHub CLI命令执行
# 提供基础的GitHub CLI操作原语

set -euo pipefail

# ==============================================================================
# GitHub操作层 - 核心原语
# ==============================================================================

# GitHub PR创建操作
github_pr_create_operation() {
    local title="$1"
    local body="$2"
    local head_branch="$3"
    local base_branch="$4"
    local worktree_path="${5:-$(pwd)}"
    
    # 基础检查
    [[ -n "$title" && -n "$head_branch" && -n "$base_branch" ]] || {
        echo "❌ 错误：PR标题、源分支和目标分支不能为空" >&2
        return 1
    }
    
    # 检查GitHub CLI
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ 错误：GitHub CLI (gh) 未安装" >&2
        return 1
    fi
    
    # 执行PR创建
    if gh -C "$worktree_path" pr create --title "$title" --body "$body" --head "$head_branch" --base "$base_branch" >/dev/null 2>&1; then
        echo "✅ 成功创建PR: $head_branch → $base_branch"
        return 0
    else
        echo "❌ 创建PR失败" >&2
        return 1
    fi
}

# GitHub PR合并操作
github_pr_merge_operation() {
    local pr_number="$1"
    local merge_method="${2:-merge}"
    local worktree_path="${3:-$(pwd)}"
    
    # 基础检查
    [[ -n "$pr_number" ]] || {
        echo "❌ 错误：PR编号不能为空" >&2
        return 1
    }
    
    # 检查GitHub CLI
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ 错误：GitHub CLI (gh) 未安装" >&2
        return 1
    fi
    
    # 执行PR合并
    local merge_flag="--merge"
    case "$merge_method" in
        "squash") merge_flag="--squash" ;;
        "rebase") merge_flag="--rebase" ;;
    esac
    
    if gh -C "$worktree_path" pr merge "$pr_number" "$merge_flag" >/dev/null 2>&1; then
        echo "✅ 成功合并PR #$pr_number"
        return 0
    else
        echo "❌ 合并PR失败: #$pr_number" >&2
        return 1
    fi
}

# GitHub认证检查操作
github_auth_check_operation() {
    local check_type="${1:-status}"
    
    # 检查GitHub CLI
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ GitHub CLI (gh) 未安装" >&2
        return 1
    fi
    
    case "$check_type" in
        "status")
            if gh auth status >/dev/null 2>&1; then
                echo "✅ GitHub CLI 已认证"
                return 0
            else
                echo "❌ GitHub CLI 未认证" >&2
                return 1
            fi
            ;;
        "login")
            gh auth login
            ;;
        *)
            echo "❌ 错误：未知的检查类型: $check_type" >&2
            return 1
            ;;
    esac
}

# GitHub PR状态查询操作
github_pr_status_query() {
    local pr_number="$1"
    local worktree_path="${2:-$(pwd)}"
    
    [[ -n "$pr_number" ]] || {
        echo "❌ 错误：PR编号不能为空" >&2
        return 1
    }
    
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ 错误：GitHub CLI (gh) 未安装" >&2
        return 1
    fi
    
    if gh -C "$worktree_path" pr view "$pr_number" --json "number,title,state,url" 2>/dev/null; then
        return 0
    else
        echo "❌ 查询PR失败: #$pr_number" >&2
        return 1
    fi
}

# ==============================================================================
# 辅助方法
# ==============================================================================

# 检查GitHub CLI可用性
github_check_cli_availability() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ 错误：GitHub CLI (gh) 未安装" >&2
        return 1
    fi
    
    if ! gh auth status >/dev/null 2>&1; then
        echo "❌ 错误：GitHub CLI 未认证" >&2
        return 1
    fi
    
    return 0
}