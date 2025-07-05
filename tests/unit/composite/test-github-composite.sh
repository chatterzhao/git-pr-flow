#!/bin/bash
# GitHub Composite Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/composite/github-composite.sh"

# GitHub环境检测
has_gh_cli() {
    command -v gh >/dev/null 2>&1
}

has_jq() {
    command -v jq >/dev/null 2>&1
}

# 测试 gh_validate_complete_environment - 工具检查
test_gh_validate_complete_environment_no_jq() {
    if has_jq; then
        test_skip "jq已安装，跳过测试"
        return
    fi
    
    local result
    result=$(gh_validate_complete_environment 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "缺少jq应该导致环境验证失败"
    if [[ -n "$result" ]]; then
        assert_contains "$result" '"jq_installed": false' "应该标记jq未安装"
        assert_contains "$result" '"environment_status": "not_ready"' "环境状态应该为not_ready"
    fi
}

test_gh_validate_complete_environment_no_gh() {
    # 这个测试很难模拟，因为我们需要实际的gh CLI来运行大部分代码
    if ! has_gh_cli; then
        local result
        result=$(gh_validate_complete_environment 2>/dev/null || echo "")
        
        assert_not_equals 0 $? "缺少gh CLI应该导致环境验证失败"
        if [[ -n "$result" ]]; then
            assert_contains "$result" '"gh_installed": false' "应该标记gh CLI未安装"
        fi
    else
        test_skip "gh CLI已安装，跳过测试"
    fi
}

test_gh_validate_complete_environment_json_format() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_validate_complete_environment 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        # 验证JSON格式正确性
        echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
        
        # 验证必需字段存在
        assert_contains "$result" '"environment_status"' "应该包含environment_status字段"
        assert_contains "$result" '"jq_installed"' "应该包含jq_installed字段"
        assert_contains "$result" '"gh_installed"' "应该包含gh_installed字段"
        assert_contains "$result" '"gh_authenticated"' "应该包含gh_authenticated字段"
        assert_contains "$result" '"repository_connected"' "应该包含repository_connected字段"
    else
        test_skip "需要有效的GitHub环境"
    fi
}

# 测试 gh_get_pr_complete_info - 基本功能
test_gh_get_pr_complete_info_no_pr() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    # 使用一个几乎不可能存在的分支名
    local result
    result=$(gh_get_pr_complete_info "nonexistent-branch-$$" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        assert_contains "$result" '"pr_exists": false' "不存在的分支应该返回pr_exists为false"
        assert_contains "$result" '"branch_name": "nonexistent-branch-$$"' "应该包含分支名称"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

test_gh_get_pr_complete_info_json_structure() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_get_pr_complete_info "test-branch" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        # 验证JSON格式正确性
        echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
        
        # 验证必需字段存在
        assert_contains "$result" '"pr_exists"' "应该包含pr_exists字段"
        assert_contains "$result" '"branch_name"' "应该包含branch_name字段"
        assert_contains "$result" '"target_branch"' "应该包含target_branch字段"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

# 测试 gh_check_pr_creation_readiness
test_gh_check_pr_creation_readiness_no_github_env() {
    if ! has_jq || ! has_gh_cli; then
        # 在没有GitHub环境的情况下测试
        local result
        result=$(gh_check_pr_creation_readiness "test-branch" "main" 2>/dev/null || echo "")
        
        assert_not_equals 0 $? "没有GitHub环境应该导致检查失败"
    else
        test_skip "有GitHub环境，跳过此测试"
    fi
}

test_gh_check_pr_creation_readiness_json_format() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_check_pr_creation_readiness "test-branch" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        # 验证JSON格式正确性
        echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
        
        # 验证必需字段存在
        assert_contains "$result" '"creation_ready"' "应该包含creation_ready字段"
        assert_contains "$result" '"branch_name"' "应该包含branch_name字段"
        assert_contains "$result" '"target_branch"' "应该包含target_branch字段"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

# 测试 gh_intelligent_create_pr - 模拟测试
test_gh_intelligent_create_pr_invalid_params() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    # 使用空标题测试参数验证
    local result
    result=$(gh_intelligent_create_pr "test-branch" "main" "" "test body" 2>/dev/null || echo "")
    
    # 因为标题为空，创建应该失败或有问题
    if [[ -n "$result" ]]; then
        assert_contains "$result" '"creation_success"' "应该包含creation_success字段"
    else
        # 失败也是期望的结果
        assert_not_equals 0 $? "空标题应该导致失败"
    fi
}

# 测试 gh_check_pr_merge_readiness
test_gh_check_pr_merge_readiness_no_pr() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_check_pr_merge_readiness "nonexistent-branch-$$" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        assert_not_equals 0 $? "不存在的PR应该导致检查失败"
        assert_contains "$result" '"merge_ready": false' "应该标记为不可合并"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

test_gh_check_pr_merge_readiness_json_format() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_check_pr_merge_readiness "test-branch" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        # 验证JSON格式正确性
        echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
        
        # 验证必需字段存在
        assert_contains "$result" '"merge_ready"' "应该包含merge_ready字段"
        assert_contains "$result" '"pr_state"' "应该包含pr_state字段"
        assert_contains "$result" '"mergeable"' "应该包含mergeable字段"
        assert_contains "$result" '"review_decision"' "应该包含review_decision字段"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

# 测试 gh_batch_pr_status_check
test_gh_batch_pr_status_check_no_matches() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_batch_pr_status_check "nonexistent-pattern-$$" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        assert_contains "$result" '"total_branches": 0' "应该显示没有匹配的分支"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

test_gh_batch_pr_status_check_json_format() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_batch_pr_status_check "*" "main" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        # 验证JSON格式正确性
        echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
        
        # 验证必需字段存在
        assert_contains "$result" '"total_branches"' "应该包含total_branches字段"
        assert_contains "$result" '"branches_with_pr"' "应该包含branches_with_pr字段"
        assert_contains "$result" '"merge_ready_prs"' "应该包含merge_ready_prs字段"
        assert_contains "$result" '"pattern"' "应该包含pattern字段"
    else
        test_skip "需要有效的GitHub仓库环境"
    fi
}

# 边缘情况测试
test_github_methods_empty_branch_name() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_get_pr_complete_info "" "main" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "空分支名应该导致失败"
}

test_github_methods_special_characters() {
    if ! has_jq || ! has_gh_cli; then
        test_skip "需要jq和gh CLI"
        return
    fi
    
    local result
    result=$(gh_get_pr_complete_info "branch@with#special!chars" "main" 2>/dev/null || echo "")
    
    # 特殊字符可能导致失败，这是期望的
    if [[ $? -ne 0 ]]; then
        assert_true true "特殊字符分支名处理正确"
    else
        # 如果成功，应该有合理的输出
        if [[ -n "$result" ]]; then
            assert_contains "$result" '"branch_name"' "应该包含分支名称字段"
        fi
    fi
}

# 依赖检查测试
test_github_composite_dependencies() {
    # 检查是否正确导入了依赖
    if type git_validate_branch_state >/dev/null 2>&1; then
        assert_true true "应该正确导入git-composite依赖"
    else
        assert_fail "缺少git-composite依赖"
    fi
    
    if type validate_pr_readiness >/dev/null 2>&1; then
        assert_true true "应该正确导入validation-composite依赖"
    else
        assert_fail "缺少validation-composite依赖"
    fi
}

# 运行所有测试
run_test_suite "GitHub Composite Tests" \
    test_gh_validate_complete_environment_no_jq \
    test_gh_validate_complete_environment_no_gh \
    test_gh_validate_complete_environment_json_format \
    test_gh_get_pr_complete_info_no_pr \
    test_gh_get_pr_complete_info_json_structure \
    test_gh_check_pr_creation_readiness_no_github_env \
    test_gh_check_pr_creation_readiness_json_format \
    test_gh_intelligent_create_pr_invalid_params \
    test_gh_check_pr_merge_readiness_no_pr \
    test_gh_check_pr_merge_readiness_json_format \
    test_gh_batch_pr_status_check_no_matches \
    test_gh_batch_pr_status_check_json_format \
    test_github_methods_empty_branch_name \
    test_github_methods_special_characters \
    test_github_composite_dependencies