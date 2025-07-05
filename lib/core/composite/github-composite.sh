#!/bin/bash
# GPF Core - GitHub Integration Composite Methods
# GitHub集成组合方法 - 组合原子方法实现GitHub操作复杂逻辑

set -euo pipefail

# 导入依赖的组合方法和原子方法
source "$(dirname "${BASH_SOURCE[0]}")/git-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/validation-composite.sh"

# 验证GitHub环境完整性
# 参数：无
# 返回：0（环境就绪）或1（环境异常），环境状态输出到stdout
gh_validate_complete_environment() {
    echo "🔍 检查GitHub环境..."
    
    # 0. 检查jq是否安装（GitHub操作需要）
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ 错误：jq 未安装，GitHub操作需要jq解析JSON" >&2
        cat << EOF
{
    "environment_status": "not_ready",
    "jq_installed": false,
    "gh_installed": false,
    "gh_authenticated": false,
    "repository_connected": false,
    "issues": ["jq未安装"]
}
EOF
        return 1
    fi
    
    # 1. 检查gh CLI是否安装
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ 错误：GitHub CLI (gh) 未安装" >&2
        cat << EOF
{
    "environment_status": "not_ready",
    "jq_installed": true,
    "gh_installed": false,
    "gh_authenticated": false,
    "repository_connected": false,
    "issues": ["GitHub CLI未安装"]
}
EOF
        return 1
    fi
    
    echo "✅ GitHub CLI已安装"
    
    # 2. 检查认证状态
    local auth_status="false"
    if gh auth status >/dev/null 2>&1; then
        auth_status="true"
        echo "✅ GitHub认证有效"
    else
        echo "❌ GitHub认证失败" >&2
        cat << EOF
{
    "environment_status": "not_ready",
    "jq_installed": true,
    "gh_installed": true,
    "gh_authenticated": false,
    "repository_connected": false,
    "issues": ["GitHub认证失败"]
}
EOF
        return 1
    fi
    
    # 3. 检查仓库连接
    local repo_connected="false"
    local repo_info=""
    if repo_info=$(gh repo view --json nameWithOwner,url 2>/dev/null); then
        repo_connected="true"
        local repo_name
        repo_name=$(echo "$repo_info" | grep -o '"nameWithOwner": "[^"]*"' | cut -d'"' -f4)
        echo "✅ 仓库连接正常：$repo_name"
    else
        echo "❌ 无法连接到GitHub仓库" >&2
        cat << EOF
{
    "environment_status": "not_ready",
    "jq_installed": true,
    "gh_installed": true,
    "gh_authenticated": true,
    "repository_connected": false,
    "issues": ["无法连接到GitHub仓库"]
}
EOF
        return 1
    fi
    
    # 4. 检查网络连接
    echo "🌐 检查网络连接..."
    if ! gh api user >/dev/null 2>&1; then
        echo "❌ GitHub网络连接失败" >&2
        cat << EOF
{
    "environment_status": "not_ready",
    "jq_installed": true,
    "gh_installed": true,
    "gh_authenticated": true,
    "repository_connected": false,
    "issues": ["GitHub网络连接失败"]
}
EOF
        return 1
    fi
    
    echo "✅ GitHub环境验证通过"
    
    cat << EOF
{
    "environment_status": "ready",
    "jq_installed": true,
    "gh_installed": true,
    "gh_authenticated": true,
    "repository_connected": true,
    "repository_info": $repo_info,
    "issues": []
}
EOF
    
    return 0
}

# 获取PR的完整信息
# 参数：(branch_name, optional: target_branch)
# 返回：PR信息JSON或错误
gh_get_pr_complete_info() {
    local branch_name="$1"
    local target_branch="${2:-develop}"
    
    echo "🔍 查找PR信息：$branch_name"
    
    # 检查GitHub环境
    if ! gh_validate_complete_environment >/dev/null; then
        echo "❌ GitHub环境不可用" >&2
        return 1
    fi
    
    # 查找PR
    local pr_info
    if pr_info=$(gh pr list --head "$branch_name" --json number,title,state,url,mergeable,reviewDecision,statusCheckRollup 2>/dev/null); then
        # 检查是否找到PR
        local pr_count
        pr_count=$(echo "$pr_info" | jq '. | length' 2>/dev/null || echo "0")
        
        if [[ "$pr_count" -eq 0 ]]; then
            echo "ℹ️ 未找到分支 $branch_name 的PR"
            cat << EOF
{
    "pr_exists": false,
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "message": "未找到PR"
}
EOF
            return 0
        fi
        
        # 获取第一个PR的详细信息
        local pr_data
        pr_data=$(echo "$pr_info" | jq '.[0]' 2>/dev/null)
        
        if [[ -z "$pr_data" ]]; then
            echo "❌ 解析PR信息失败" >&2
            return 1
        fi
        
        # 提取关键信息
        local pr_number pr_title pr_state pr_url mergeable review_decision
        pr_number=$(echo "$pr_data" | jq -r '.number // "unknown"')
        pr_title=$(echo "$pr_data" | jq -r '.title // "unknown"')
        pr_state=$(echo "$pr_data" | jq -r '.state // "unknown"')
        pr_url=$(echo "$pr_data" | jq -r '.url // "unknown"')
        mergeable=$(echo "$pr_data" | jq -r '.mergeable // "unknown"')
        review_decision=$(echo "$pr_data" | jq -r '.reviewDecision // "PENDING"')
        
        # 检查状态检查
        local status_checks_passing="unknown"
        local status_summary=""
        if echo "$pr_data" | jq -e '.statusCheckRollup' >/dev/null 2>&1; then
            local status_rollup
            status_rollup=$(echo "$pr_data" | jq '.statusCheckRollup // []')
            local total_checks failed_checks
            total_checks=$(echo "$status_rollup" | jq '. | length')
            failed_checks=$(echo "$status_rollup" | jq '[.[] | select(.state != "SUCCESS")] | length')
            
            if [[ "$failed_checks" -eq 0 && "$total_checks" -gt 0 ]]; then
                status_checks_passing="true"
                status_summary="所有检查通过 ($total_checks/$total_checks)"
            elif [[ "$total_checks" -eq 0 ]]; then
                status_checks_passing="none"
                status_summary="无状态检查"
            else
                status_checks_passing="false"
                status_summary="检查失败 ($failed_checks/$total_checks)"
            fi
        fi
        
        echo "✅ 找到PR #$pr_number：$pr_title"
        
        cat << EOF
{
    "pr_exists": true,
    "pr_number": $pr_number,
    "pr_title": "$pr_title",
    "pr_state": "$pr_state",
    "pr_url": "$pr_url",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "mergeable": "$mergeable",
    "review_decision": "$review_decision",
    "status_checks_passing": "$status_checks_passing",
    "status_summary": "$status_summary",
    "raw_data": $pr_data
}
EOF
        
    else
        echo "❌ 查询PR失败" >&2
        return 1
    fi
    
    return 0
}

# 检查PR创建就绪状态
# 参数：(branch_name, target_branch, optional: worktree_path)
# 返回：0（就绪）或1（未就绪），就绪状态输出到stdout
gh_check_pr_creation_readiness() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    echo "🔍 检查PR创建就绪状态..."
    
    # 1. 验证GitHub环境
    local gh_env
    if ! gh_env=$(gh_validate_complete_environment); then
        echo "❌ GitHub环境验证失败" >&2
        return 1
    fi
    
    # 2. 检查PR是否已存在
    local pr_info
    pr_info=$(gh_get_pr_complete_info "$branch_name" "$target_branch" 2>/dev/null)
    local pr_exists
    pr_exists=$(echo "$pr_info" | grep -o '"pr_exists": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    if [[ "$pr_exists" == "true" ]]; then
        local pr_number pr_url
        pr_number=$(echo "$pr_info" | grep -o '"pr_number": [^,]*' | cut -d':' -f2 | tr -d ' ')
        pr_url=$(echo "$pr_info" | grep -o '"pr_url": "[^"]*"' | cut -d'"' -f4)
        
        echo "ℹ️ PR已存在：#$pr_number"
        cat << EOF
{
    "creation_ready": false,
    "reason": "PR已存在",
    "existing_pr": {
        "number": $pr_number,
        "url": "$pr_url"
    }
}
EOF
        return 1
    fi
    
    # 3. 验证分支PR就绪状态
    local validation_result
    if ! validation_result=$(validate_pr_readiness "$branch_name" "$target_branch" "$worktree_path"); then
        echo "❌ 分支PR验证失败" >&2
        cat << EOF
{
    "creation_ready": false,
    "reason": "分支状态未就绪",
    "validation_result": $validation_result
}
EOF
        return 1
    fi
    
    # 4. 检查分支是否推送到远程
    local branch_state
    branch_state=$(git_validate_branch_state "$branch_name" "$worktree_path")
    local remote_exists
    remote_exists=$(echo "$branch_state" | grep -o '"remote_exists": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    if [[ "$remote_exists" != "true" ]]; then
        echo "❌ 分支未推送到远程" >&2
        cat << EOF
{
    "creation_ready": false,
    "reason": "分支未推送到远程",
    "branch_state": $branch_state
}
EOF
        return 1
    fi
    
    echo "✅ PR创建就绪状态验证通过"
    
    cat << EOF
{
    "creation_ready": true,
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "github_environment": $gh_env,
    "validation_result": $validation_result,
    "branch_state": $branch_state
}
EOF
    
    return 0
}

# 智能创建PR
# 参数：(branch_name, target_branch, pr_title, pr_body, optional: worktree_path)
# 返回：0（成功）或1（失败），创建结果输出到stdout
gh_intelligent_create_pr() {
    local branch_name="$1"
    local target_branch="$2"
    local pr_title="$3"
    local pr_body="$4"
    local worktree_path="${5:-$(pwd)}"
    
    echo "🚀 智能创建PR..."
    
    # 1. 检查创建就绪状态
    local readiness_check
    if ! readiness_check=$(gh_check_pr_creation_readiness "$branch_name" "$target_branch" "$worktree_path"); then
        echo "❌ PR创建就绪检查失败" >&2
        return 1
    fi
    
    # 2. 准备PR参数
    local create_cmd="gh pr create --head '$branch_name' --base '$target_branch' --title '$pr_title'"
    
    if [[ -n "$pr_body" ]]; then
        create_cmd="$create_cmd --body '$pr_body'"
    fi
    
    echo "📝 创建PR: $pr_title"
    echo "🎯 目标分支: $target_branch"
    
    # 3. 执行PR创建
    local pr_url
    if pr_url=$(eval "$create_cmd" 2>/dev/null); then
        echo "✅ PR创建成功"
        echo "🔗 PR地址: $pr_url"
        
        # 4. 获取创建后的PR信息
        local pr_info
        pr_info=$(gh_get_pr_complete_info "$branch_name" "$target_branch" 2>/dev/null)
        
        cat << EOF
{
    "creation_success": true,
    "pr_url": "$pr_url",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "pr_title": "$pr_title",
    "pr_info": $pr_info
}
EOF
        
        return 0
    else
        echo "❌ PR创建失败" >&2
        cat << EOF
{
    "creation_success": false,
    "error": "GitHub PR创建命令执行失败",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch"
}
EOF
        return 1
    fi
}

# 检查PR合并就绪状态
# 参数：(branch_name, optional: target_branch)
# 返回：0（可合并）或1（不可合并），合并状态输出到stdout
gh_check_pr_merge_readiness() {
    local branch_name="$1"
    local target_branch="${2:-develop}"
    
    echo "🔍 检查PR合并就绪状态..."
    
    # 1. 获取PR信息
    local pr_info
    if ! pr_info=$(gh_get_pr_complete_info "$branch_name" "$target_branch"); then
        echo "❌ 获取PR信息失败" >&2
        return 1
    fi
    
    # 检查PR是否存在
    local pr_exists
    pr_exists=$(echo "$pr_info" | grep -o '"pr_exists": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    if [[ "$pr_exists" != "true" ]]; then
        echo "❌ PR不存在" >&2
        cat << EOF
{
    "merge_ready": false,
    "reason": "PR不存在",
    "pr_info": $pr_info
}
EOF
        return 1
    fi
    
    # 2. 提取PR状态信息
    local pr_state mergeable review_decision status_checks_passing
    pr_state=$(echo "$pr_info" | grep -o '"pr_state": "[^"]*"' | cut -d'"' -f4)
    mergeable=$(echo "$pr_info" | grep -o '"mergeable": "[^"]*"' | cut -d'"' -f4)
    review_decision=$(echo "$pr_info" | grep -o '"review_decision": "[^"]*"' | cut -d'"' -f4)
    status_checks_passing=$(echo "$pr_info" | grep -o '"status_checks_passing": "[^"]*"' | cut -d'"' -f4)
    
    # 3. 评估合并就绪状态
    local merge_ready="true"
    local blocking_issues=()
    local warnings=()
    
    # 检查PR状态
    if [[ "$pr_state" != "OPEN" ]]; then
        merge_ready="false"
        blocking_issues+=("PR状态为 $pr_state，不是OPEN状态")
    fi
    
    # 检查可合并性
    if [[ "$mergeable" == "CONFLICTING" ]]; then
        merge_ready="false"
        blocking_issues+=("存在合并冲突")
    elif [[ "$mergeable" == "UNKNOWN" ]]; then
        warnings+=("合并状态未知，需要进一步检查")
    fi
    
    # 检查审查状态
    case "$review_decision" in
        "APPROVED")
            echo "✅ 代码审查已通过"
            ;;
        "CHANGES_REQUESTED")
            merge_ready="false"
            blocking_issues+=("代码审查要求修改")
            ;;
        "REVIEW_REQUIRED")
            warnings+=("需要代码审查")
            ;;
        "PENDING"|*)
            warnings+=("代码审查待处理")
            ;;
    esac
    
    # 检查状态检查
    case "$status_checks_passing" in
        "true")
            echo "✅ 所有状态检查通过"
            ;;
        "false")
            merge_ready="false"
            blocking_issues+=("状态检查失败")
            ;;
        "none")
            warnings+=("无状态检查配置")
            ;;
        *)
            warnings+=("状态检查状态未知")
            ;;
    esac
    
    # 4. 输出结果
    cat << EOF
{
    "merge_ready": $merge_ready,
    "pr_state": "$pr_state",
    "mergeable": "$mergeable",
    "review_decision": "$review_decision",
    "status_checks_passing": "$status_checks_passing",
    "blocking_issues": [$(printf '"%s",' "${blocking_issues[@]}" | sed 's/,$//')]",
    "warnings": [$(printf '"%s",' "${warnings[@]}" | sed 's/,$//')]",
    "pr_info": $pr_info
}
EOF
    
    if [[ "$merge_ready" == "true" ]]; then
        echo "✅ PR合并就绪"
        if [[ ${#warnings[@]} -gt 0 ]]; then
            echo "⚠️ 注意事项："
            printf '  - %s\n' "${warnings[@]}"
        fi
        return 0
    else
        echo "❌ PR未合并就绪"
        printf '  - %s\n' "${blocking_issues[@]}"
        return 1
    fi
}

# 批量PR状态检查
# 参数：(pattern, optional: target_branch)
# pattern: 分支名匹配模式，如 "epic-*" 或 "*-ef"
# 返回：批量检查结果
gh_batch_pr_status_check() {
    local pattern="$1"
    local target_branch="${2:-develop}"
    
    echo "🔍 批量检查PR状态：$pattern"
    
    # 1. 验证GitHub环境
    if ! gh_validate_complete_environment >/dev/null; then
        echo "❌ GitHub环境不可用" >&2
        return 1
    fi
    
    # 2. 获取匹配的分支
    local matching_branches
    matching_branches=$(git branch -r | grep -E "origin/${pattern//\*/.*}" | sed 's/origin\///' | tr -d ' ')
    
    if [[ -z "$matching_branches" ]]; then
        echo "ℹ️ 没有找到匹配模式 '$pattern' 的远程分支"
        return 0
    fi
    
    echo "📋 找到匹配分支："
    echo "$matching_branches" | sed 's/^/  - /'
    
    # 3. 逐个检查PR状态
    local total_count=0 pr_exists_count=0 merge_ready_count=0
    
    echo ""
    echo "🔍 检查PR状态："
    
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        ((total_count++))
        
        echo "  📝 检查分支: $branch"
        
        local pr_info
        pr_info=$(gh_get_pr_complete_info "$branch" "$target_branch" 2>/dev/null)
        local pr_exists
        pr_exists=$(echo "$pr_info" | grep -o '"pr_exists": [^,]*' | cut -d':' -f2 | tr -d ' ')
        
        if [[ "$pr_exists" == "true" ]]; then
            ((pr_exists_count++))
            local pr_number pr_state
            pr_number=$(echo "$pr_info" | grep -o '"pr_number": [^,]*' | cut -d':' -f2 | tr -d ' ')
            pr_state=$(echo "$pr_info" | grep -o '"pr_state": "[^"]*"' | cut -d'"' -f4)
            
            echo "    ✅ PR #$pr_number ($pr_state)"
            
            # 检查合并就绪状态
            local merge_status
            if merge_status=$(gh_check_pr_merge_readiness "$branch" "$target_branch" 2>/dev/null); then
                local merge_ready
                merge_ready=$(echo "$merge_status" | grep -o '"merge_ready": [^,]*' | cut -d':' -f2 | tr -d ' ')
                if [[ "$merge_ready" == "true" ]]; then
                    ((merge_ready_count++))
                    echo "    🚀 可合并"
                else
                    echo "    ⏳ 待处理"
                fi
            fi
        else
            echo "    ❌ 无PR"
        fi
    done <<< "$matching_branches"
    
    # 4. 输出统计结果
    echo ""
    echo "📊 统计结果："
    echo "  - 总分支数: $total_count"
    echo "  - 有PR的分支: $pr_exists_count"
    echo "  - 可合并的PR: $merge_ready_count"
    
    cat << EOF
{
    "total_branches": $total_count,
    "branches_with_pr": $pr_exists_count,
    "merge_ready_prs": $merge_ready_count,
    "pattern": "$pattern",
    "target_branch": "$target_branch"
}
EOF
    
    return 0
}