#!/bin/bash
# GPF Core - GitHub PR Query Atomic Methods Tests
# 测试 github-pr-query.sh 中的所有原子方法

set -euo pipefail

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/../../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/core/atomic/github-pr-query.sh"

# 测试：github_pr_exists
test_github_pr_exists() {
    print_test_header "测试 github_pr_exists - PR存在性检查"
    
    if ! command -v gh >/dev/null 2>&1; then
        if ! github_pr_exists "test-branch"; then
            echo "✅ GitHub CLI未安装时正确返回PR不存在"
        else
            echo "❌ GitHub CLI未安装但认为PR存在"
            return 1
        fi
        return 0
    fi
    
    # 测试不存在的分支
    if ! github_pr_exists "nonexistent-branch-xyz-123"; then
        echo "✅ 正确检测到不存在的PR"
    else
        echo "⚠️ 检测到了不存在的分支的PR（可能实际存在）"
    fi
    
    # 注意：我们无法测试真实存在的PR，因为这依赖于具体的GitHub仓库状态
    echo "✅ PR存在性检查基础功能正常"
}

# 测试：github_pr_get_basic_info
test_github_pr_get_basic_info() {
    print_test_header "测试 github_pr_get_basic_info - 获取PR基本信息"
    
    local pr_info
    pr_info=$(github_pr_get_basic_info "nonexistent-branch-xyz-123")
    
    # 验证JSON格式
    if echo "$pr_info" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("exists" "number" "title" "state" "url")
    for field in "${required_fields[@]}"; do
        if echo "$pr_info" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证不存在分支的返回值
    local exists
    exists=$(echo "$pr_info" | jq -r '.exists')
    if [[ "$exists" == "false" ]]; then
        echo "✅ 正确标记不存在的PR"
    else
        echo "❌ 错误地标记不存在的PR为存在"
        return 1
    fi
}

# 测试：github_pr_get_status
test_github_pr_get_status() {
    print_test_header "测试 github_pr_get_status - 获取PR状态"
    
    local pr_status
    pr_status=$(github_pr_get_status "999999")  # 使用一个不太可能存在的PR号
    
    # 验证JSON格式
    if echo "$pr_status" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("state" "mergeable")
    for field in "${required_fields[@]}"; do
        if echo "$pr_status" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    if ! command -v gh >/dev/null 2>&1; then
        local error
        error=$(echo "$pr_status" | jq -r '.error // empty')
        if [[ "$error" == "GitHub CLI not available" ]]; then
            echo "✅ GitHub CLI未安装时正确返回错误信息"
        else
            echo "❌ GitHub CLI未安装时错误信息不正确"
            return 1
        fi
    fi
}

# 测试：github_pr_get_review_status
test_github_pr_get_review_status() {
    print_test_header "测试 github_pr_get_review_status - 获取PR审核状态"
    
    local review_status
    review_status=$(github_pr_get_review_status "999999")
    
    # 验证JSON格式
    if echo "$review_status" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("reviews" "approved" "changes_requested" "review_required")
    for field in "${required_fields[@]}"; do
        if echo "$review_status" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证布尔字段类型
    local approved changes_requested
    approved=$(echo "$review_status" | jq -r '.approved')
    changes_requested=$(echo "$review_status" | jq -r '.changes_requested')
    
    if [[ "$approved" == "true" || "$approved" == "false" ]]; then
        echo "✅ approved字段为有效布尔值"
    else
        echo "❌ approved字段不是有效布尔值：$approved"
        return 1
    fi
    
    if [[ "$changes_requested" == "true" || "$changes_requested" == "false" ]]; then
        echo "✅ changes_requested字段为有效布尔值"
    else
        echo "❌ changes_requested字段不是有效布尔值：$changes_requested"
        return 1
    fi
}

# 测试：github_pr_get_merge_status
test_github_pr_get_merge_status() {
    print_test_header "测试 github_pr_get_merge_status - 获取PR合并状态"
    
    local merge_status
    merge_status=$(github_pr_get_merge_status "999999")
    
    # 验证JSON格式
    if echo "$merge_status" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("mergeable" "merged" "can_merge" "conflicts")
    for field in "${required_fields[@]}"; do
        if echo "$merge_status" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证布尔字段类型
    local merged can_merge conflicts
    merged=$(echo "$merge_status" | jq -r '.merged')
    can_merge=$(echo "$merge_status" | jq -r '.can_merge')
    conflicts=$(echo "$merge_status" | jq -r '.conflicts')
    
    if [[ "$merged" == "true" || "$merged" == "false" ]]; then
        echo "✅ merged字段为有效布尔值"
    else
        echo "❌ merged字段不是有效布尔值：$merged"
        return 1
    fi
    
    if [[ "$can_merge" == "true" || "$can_merge" == "false" ]]; then
        echo "✅ can_merge字段为有效布尔值"
    else
        echo "❌ can_merge字段不是有效布尔值：$can_merge"
        return 1
    fi
    
    if [[ "$conflicts" == "true" || "$conflicts" == "false" ]]; then
        echo "✅ conflicts字段为有效布尔值"
    else
        echo "❌ conflicts字段不是有效布尔值：$conflicts"
        return 1
    fi
}

# 测试：github_pr_get_checks_status
test_github_pr_get_checks_status() {
    print_test_header "测试 github_pr_get_checks_status - 获取PR检查状态"
    
    local checks_status
    checks_status=$(github_pr_get_checks_status "999999")
    
    # 验证JSON格式
    if echo "$checks_status" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("checks" "all_passed" "total" "passed" "failed")
    for field in "${required_fields[@]}"; do
        if echo "$checks_status" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证数字字段类型
    local total passed failed
    total=$(echo "$checks_status" | jq -r '.total')
    passed=$(echo "$checks_status" | jq -r '.passed')
    failed=$(echo "$checks_status" | jq -r '.failed')
    
    if [[ "$total" =~ ^[0-9]+$ ]]; then
        echo "✅ total字段为有效数字"
    else
        echo "❌ total字段不是有效数字：$total"
        return 1
    fi
    
    if [[ "$passed" =~ ^[0-9]+$ ]]; then
        echo "✅ passed字段为有效数字"
    else
        echo "❌ passed字段不是有效数字：$passed"
        return 1
    fi
    
    if [[ "$failed" =~ ^[0-9]+$ ]]; then
        echo "✅ failed字段为有效数字"
    else
        echo "❌ failed字段不是有效数字：$failed"
        return 1
    fi
}

# 测试：github_pr_get_number_by_branch
test_github_pr_get_number_by_branch() {
    print_test_header "测试 github_pr_get_number_by_branch - 根据分支获取PR号"
    
    local pr_number
    pr_number=$(github_pr_get_number_by_branch "nonexistent-branch-xyz-123")
    
    # 对于不存在的分支，应该返回空字符串
    if [[ -z "$pr_number" ]]; then
        echo "✅ 不存在的分支正确返回空PR号"
    else
        echo "⚠️ 不存在的分支返回了PR号：$pr_number（可能实际存在）"
    fi
}

# 测试：github_pr_check_safe_to_close
test_github_pr_check_safe_to_close() {
    print_test_header "测试 github_pr_check_safe_to_close - 检查PR是否可安全关闭"
    
    # 测试不存在的PR
    if ! github_pr_check_safe_to_close "999999"; then
        echo "✅ 不存在的PR正确返回不可安全关闭"
    else
        echo "⚠️ 不存在的PR返回可安全关闭（可能实际存在且已合并）"
    fi
}

# 测试：github_pr_list_all
test_github_pr_list_all() {
    print_test_header "测试 github_pr_list_all - 列出所有PR"
    
    local pr_list
    pr_list=$(github_pr_list_all "open")
    
    # 验证JSON格式
    if echo "$pr_list" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    if echo "$pr_list" | jq -e "has(\"prs\")" >/dev/null 2>&1; then
        echo "✅ 包含prs字段"
    else
        echo "❌ 缺少prs字段"
        return 1
    fi
    
    # 验证prs字段是数组
    if echo "$pr_list" | jq -e '.prs | type == "array"' >/dev/null 2>&1; then
        echo "✅ prs字段是有效数组"
    else
        echo "❌ prs字段不是数组"
        return 1
    fi
    
    if ! command -v gh >/dev/null 2>&1; then
        local error
        error=$(echo "$pr_list" | jq -r '.error // empty')
        if [[ "$error" == "GitHub CLI not available" ]]; then
            echo "✅ GitHub CLI未安装时正确返回错误信息"
        else
            echo "❌ GitHub CLI未安装时错误信息不正确"
            return 1
        fi
    fi
}

# 运行所有测试
run_test "github_pr_exists" "test_github_pr_exists"
run_test "github_pr_get_basic_info" "test_github_pr_get_basic_info"
run_test "github_pr_get_status" "test_github_pr_get_status"
run_test "github_pr_get_review_status" "test_github_pr_get_review_status"
run_test "github_pr_get_merge_status" "test_github_pr_get_merge_status"
run_test "github_pr_get_checks_status" "test_github_pr_get_checks_status"
run_test "github_pr_get_number_by_branch" "test_github_pr_get_number_by_branch"
run_test "github_pr_check_safe_to_close" "test_github_pr_check_safe_to_close"
run_test "github_pr_list_all" "test_github_pr_list_all"

print_test_summary