#!/bin/bash
# GPF Core - GitHub PR Query Atomic Methods
# GitHub PR查询原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 检查PR是否存在
# 参数：(branch_name, optional: worktree_path)
# 返回：0（存在）或1（不存在）
github_pr_exists() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 检查GitHub CLI可用性
    if ! command -v gh >/dev/null 2>&1; then
        return 1
    fi
    
    # 检查是否有对应的PR
    local pr_count
    pr_count=$(gh -R . pr list --head "$branch_name" --json number --jq 'length' 2>/dev/null) || pr_count=0
    
    [[ "$pr_count" -gt 0 ]]
}

# 获取PR基本信息
# 参数：(branch_name, optional: worktree_path)
# 返回：JSON格式的PR基本信息
github_pr_get_basic_info() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if ! github_pr_exists "$branch_name" "$worktree_path"; then
        cat << EOF
{
    "exists": false,
    "number": null,
    "title": null,
    "state": null,
    "url": null,
    "error": "PR not found for branch: $branch_name"
}
EOF
        return 1
    fi
    
    # 获取PR信息
    local pr_info
    if pr_info=$(gh -R . pr list --head "$branch_name" --json number,title,state,url --jq '.[0]' 2>/dev/null); then
        echo "$pr_info" | jq '. + {"exists": true}'
    else
        cat << EOF
{
    "exists": false,
    "number": null,
    "title": null,
    "state": null,
    "url": null,
    "error": "Failed to fetch PR information"
}
EOF
        return 1
    fi
}

# 获取PR状态信息
# 参数：(pr_number, optional: worktree_path)
# 返回：JSON格式的PR状态信息
github_pr_get_status() {
    local pr_number="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if ! command -v gh >/dev/null 2>&1; then
        cat << EOF
{
    "state": "unknown",
    "mergeable": null,
    "checks": null,
    "error": "GitHub CLI not available"
}
EOF
        return 1
    fi
    
    # 获取PR状态
    local pr_status
    if pr_status=$(gh -R . pr view "$pr_number" --json state,mergeable,statusCheckRollupState 2>/dev/null); then
        echo "$pr_status"
    else
        cat << EOF
{
    "state": "unknown",
    "mergeable": null,
    "checks": null,
    "error": "Failed to fetch PR status for #$pr_number"
}
EOF
        return 1
    fi
}

# 获取PR审核状态
# 参数：(pr_number, optional: worktree_path)
# 返回：JSON格式的审核状态信息
github_pr_get_review_status() {
    local pr_number="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if ! command -v gh >/dev/null 2>&1; then
        cat << EOF
{
    "reviews": [],
    "approved": false,
    "changes_requested": false,
    "review_required": true,
    "error": "GitHub CLI not available"
}
EOF
        return 1
    fi
    
    # 获取审核状态
    local reviews
    if reviews=$(gh -R . pr view "$pr_number" --json reviews --jq '.reviews' 2>/dev/null); then
        local approved="false"
        local changes_requested="false"
        
        # 检查审核状态
        if echo "$reviews" | jq -e '.[] | select(.state == "APPROVED")' >/dev/null 2>&1; then
            approved="true"
        fi
        
        if echo "$reviews" | jq -e '.[] | select(.state == "CHANGES_REQUESTED")' >/dev/null 2>&1; then
            changes_requested="true"
        fi
        
        cat << EOF
{
    "reviews": $reviews,
    "approved": $approved,
    "changes_requested": $changes_requested,
    "review_required": true
}
EOF
    else
        cat << EOF
{
    "reviews": [],
    "approved": false,
    "changes_requested": false,
    "review_required": true,
    "error": "Failed to fetch review status for #$pr_number"
}
EOF
        return 1
    fi
}

# 获取PR合并状态
# 参数：(pr_number, optional: worktree_path)
# 返回：JSON格式的合并状态信息
github_pr_get_merge_status() {
    local pr_number="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if ! command -v gh >/dev/null 2>&1; then
        cat << EOF
{
    "mergeable": null,
    "merged": false,
    "can_merge": false,
    "conflicts": false,
    "error": "GitHub CLI not available"
}
EOF
        return 1
    fi
    
    # 获取合并状态
    local merge_info
    if merge_info=$(gh -R . pr view "$pr_number" --json mergeable,merged,state 2>/dev/null); then
        local mergeable merged state
        mergeable=$(echo "$merge_info" | jq -r '.mergeable // "UNKNOWN"')
        merged=$(echo "$merge_info" | jq -r '.merged')
        state=$(echo "$merge_info" | jq -r '.state')
        
        local can_merge="false"
        local conflicts="false"
        
        if [[ "$mergeable" == "MERGEABLE" && "$merged" == "false" && "$state" == "OPEN" ]]; then
            can_merge="true"
        elif [[ "$mergeable" == "CONFLICTING" ]]; then
            conflicts="true"
        fi
        
        cat << EOF
{
    "mergeable": "$mergeable",
    "merged": $merged,
    "can_merge": $can_merge,
    "conflicts": $conflicts,
    "state": "$state"
}
EOF
    else
        cat << EOF
{
    "mergeable": null,
    "merged": false,
    "can_merge": false,
    "conflicts": false,
    "error": "Failed to fetch merge status for #$pr_number"
}
EOF
        return 1
    fi
}

# 获取PR检查状态
# 参数：(pr_number, optional: worktree_path)
# 返回：JSON格式的检查状态信息
github_pr_get_checks_status() {
    local pr_number="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if ! command -v gh >/dev/null 2>&1; then
        cat << EOF
{
    "checks": [],
    "all_passed": false,
    "total": 0,
    "passed": 0,
    "failed": 0,
    "error": "GitHub CLI not available"
}
EOF
        return 1
    fi
    
    # 获取检查状态
    local checks_info
    if checks_info=$(gh -R . pr checks "$pr_number" --json state,name,conclusion 2>/dev/null); then
        local total passed failed all_passed
        total=$(echo "$checks_info" | jq 'length')
        passed=$(echo "$checks_info" | jq '[.[] | select(.state == "COMPLETED" and .conclusion == "SUCCESS")] | length')
        failed=$(echo "$checks_info" | jq '[.[] | select(.state == "COMPLETED" and .conclusion != "SUCCESS")] | length')
        
        if [[ "$total" -gt 0 && "$passed" -eq "$total" ]]; then
            all_passed="true"
        else
            all_passed="false"
        fi
        
        cat << EOF
{
    "checks": $checks_info,
    "all_passed": $all_passed,
    "total": $total,
    "passed": $passed,
    "failed": $failed
}
EOF
    else
        cat << EOF
{
    "checks": [],
    "all_passed": false,
    "total": 0,
    "passed": 0,
    "failed": 0,
    "error": "Failed to fetch checks status for #$pr_number"
}
EOF
        return 1
    fi
}

# 根据分支名获取PR号码
# 参数：(branch_name, optional: worktree_path)
# 返回：PR号码 或 空字符串（未找到）
github_pr_get_number_by_branch() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if ! github_pr_exists "$branch_name" "$worktree_path"; then
        echo ""
        return 1
    fi
    
    gh -R . pr list --head "$branch_name" --json number --jq '.[0].number' 2>/dev/null || echo ""
}

# 检查PR是否可以安全关闭
# 参数：(pr_number, optional: worktree_path)
# 返回：0（可安全关闭）或1（不安全）
github_pr_check_safe_to_close() {
    local pr_number="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 获取PR状态
    local pr_status
    pr_status=$(github_pr_get_status "$pr_number" "$worktree_path") || return 1
    
    local state merged
    state=$(echo "$pr_status" | jq -r '.state')
    merged=$(echo "$pr_status" | jq -r '.merged')
    
    # 已合并或已关闭的PR可以安全操作
    if [[ "$merged" == "true" || "$state" == "CLOSED" ]]; then
        return 0
    fi
    
    # 开放的PR需要进一步检查
    if [[ "$state" == "OPEN" ]]; then
        # 这里可以添加更多安全检查逻辑
        # 例如：检查是否有未解决的评论、是否有pending的检查等
        return 1
    fi
    
    return 1
}

# 列出仓库中所有PR
# 参数：(optional: state, optional: worktree_path)
# 返回：JSON格式的PR列表
github_pr_list_all() {
    local state="${1:-open}"  # open, closed, merged, all
    local worktree_path="${2:-$(pwd)}"
    
    if ! command -v gh >/dev/null 2>&1; then
        echo '{"prs": [], "error": "GitHub CLI not available"}'
        return 1
    fi
    
    # 获取PR列表
    local prs
    if prs=$(gh -R . pr list --state "$state" --json number,title,headRefName,state,url 2>/dev/null); then
        echo "$prs" | jq '{prs: .}'
    else
        echo '{"prs": [], "error": "Failed to fetch PR list"}'
        return 1
    fi
}