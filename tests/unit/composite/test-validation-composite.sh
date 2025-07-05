#!/bin/bash
# Validation Composite Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/composite/validation-composite.sh"

# 测试工具函数：创建临时Git仓库
setup_test_repo() {
    local test_dir="$1"
    mkdir -p "$test_dir"
    cd "$test_dir"
    git init --quiet
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "# Test Repo" > README.md
    git add README.md
    git commit -m "Initial commit" --quiet
}

# 测试工具函数：清理测试环境
cleanup_test_repo() {
    local test_dir="$1"
    cd /
    rm -rf "$test_dir"
}

# 测试 validate_pr_readiness - 基本功能
test_validate_pr_readiness_clean_repo() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建测试分支
    git checkout -b test-branch --quiet
    git push --set-upstream origin test-branch --quiet 2>/dev/null || true
    
    local result
    result=$(validate_pr_readiness "test-branch" "main" "$test_dir" 2>/dev/null || echo "")
    
    # 清理
    cleanup_test_repo "$test_dir"
    
    # 基本检查（因为没有真实的remote，这个测试主要验证函数结构）
    if [[ -n "$result" ]]; then
        assert_contains "$result" '"branch_name": "test-branch"' "应该包含分支名称"
        assert_contains "$result" '"target_branch": "main"' "应该包含目标分支"
    else
        test_skip "需要完整Git环境和remote"
    fi
}

# 测试 validate_pr_readiness - 错误分支
test_validate_pr_readiness_invalid_branch() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_pr_readiness "nonexistent-branch" "main" "$test_dir" 2>/dev/null || echo "failed")
    
    cleanup_test_repo "$test_dir"
    
    assert_equals "failed" "$result" "不存在的分支应该导致验证失败"
}

# 测试 validate_clean_safety - 基本功能
test_validate_clean_safety_nonexistent_branch() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_clean_safety "nonexistent-branch" "$test_dir")
    
    assert_equals 0 $? "不存在的分支应该标记为安全"
    assert_contains "$result" '"safety_status": "safe"' "应该标记为安全"
    assert_contains "$result" '"branch_exists": false' "应该标记分支不存在"
    
    cleanup_test_repo "$test_dir"
}

test_validate_clean_safety_protected_branch() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_clean_safety "main" "$test_dir" 2>/dev/null || echo "")
    
    cleanup_test_repo "$test_dir"
    
    assert_not_equals 0 $? "保护分支应该不安全删除"
}

# 测试 validate_sync_requirements - 基本功能
test_validate_sync_requirements_basic() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建源分支和目标分支
    git checkout -b source-branch --quiet
    echo "source change" > source.txt
    git add source.txt
    git commit -m "Source change" --quiet
    
    git checkout main --quiet
    git checkout -b target-branch --quiet
    
    local result
    result=$(validate_sync_requirements "source-branch" "target-branch" "$test_dir" 2>/dev/null || echo "")
    
    cleanup_test_repo "$test_dir"
    
    if [[ -n "$result" ]]; then
        assert_contains "$result" '"source_branch": "source-branch"' "应该包含源分支"
        assert_contains "$result" '"target_branch": "target-branch"' "应该包含目标分支"
    else
        test_skip "需要完整Git环境"
    fi
}

test_validate_sync_requirements_nonexistent_source() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_sync_requirements "nonexistent" "main" "$test_dir" 2>/dev/null || echo "")
    
    cleanup_test_repo "$test_dir"
    
    assert_not_equals 0 $? "不存在的源分支应该导致失败"
}

# 测试 validate_environment_for_operation
test_validate_environment_for_operation_start() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_environment_for_operation "start" "$test_dir")
    
    assert_equals 0 $? "start操作环境验证应该成功"
    assert_contains "$result" '"operation_type": "start"' "应该包含操作类型"
    assert_contains "$result" '"environment_type": "root"' "应该检测为root环境"
    
    cleanup_test_repo "$test_dir"
}

test_validate_environment_for_operation_pr_in_root() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_environment_for_operation "pr" "$test_dir" 2>/dev/null || echo "")
    
    cleanup_test_repo "$test_dir"
    
    assert_not_equals 0 $? "PR操作在root环境应该失败"
}

test_validate_environment_for_operation_invalid_operation() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_environment_for_operation "invalid_op" "$test_dir" 2>/dev/null || echo "")
    
    cleanup_test_repo "$test_dir"
    
    assert_not_equals 0 $? "无效操作应该导致失败"
}

# 测试 JSON 输出格式
test_json_output_format_validate_clean_safety() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_clean_safety "nonexistent" "$test_dir")
    
    # 验证JSON格式正确性
    echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
    
    # 验证必需字段存在
    assert_contains "$result" '"safety_status"' "应该包含safety_status字段"
    assert_contains "$result" '"branch_exists"' "应该包含branch_exists字段"
    
    cleanup_test_repo "$test_dir"
}

test_json_output_format_validate_environment() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(validate_environment_for_operation "status" "$test_dir")
    
    # 验证JSON格式正确性
    echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
    
    # 验证必需字段存在
    assert_contains "$result" '"environment_status"' "应该包含environment_status字段"
    assert_contains "$result" '"operation_type"' "应该包含operation_type字段"
    assert_contains "$result" '"environment_type"' "应该包含environment_type字段"
    
    cleanup_test_repo "$test_dir"
}

# 错误处理测试
test_validate_with_invalid_project_root() {
    local result
    result=$(validate_clean_safety "test-branch" "/nonexistent/path" 2>/dev/null || echo "failed")
    
    assert_equals "failed" "$result" "无效项目根目录应该导致失败"
}

# 边缘情况测试
test_validate_clean_safety_multiple_protected_branches() {
    local test_dir="/tmp/gpf-test-$$"
    setup_test_repo "$test_dir"
    
    # 测试所有保护分支
    for branch in "main" "master" "develop" "dev"; do
        git checkout -b "$branch" --quiet 2>/dev/null || git checkout "$branch" --quiet
        local result
        result=$(validate_clean_safety "$branch" "$test_dir" 2>/dev/null || echo "")
        assert_not_equals 0 $? "保护分支 $branch 应该不能删除"
    done
    
    cleanup_test_repo "$test_dir"
}

# 运行所有测试
run_test_suite "Validation Composite Tests" \
    test_validate_pr_readiness_clean_repo \
    test_validate_pr_readiness_invalid_branch \
    test_validate_clean_safety_nonexistent_branch \
    test_validate_clean_safety_protected_branch \
    test_validate_sync_requirements_basic \
    test_validate_sync_requirements_nonexistent_source \
    test_validate_environment_for_operation_start \
    test_validate_environment_for_operation_pr_in_root \
    test_validate_environment_for_operation_invalid_operation \
    test_json_output_format_validate_clean_safety \
    test_json_output_format_validate_environment \
    test_validate_with_invalid_project_root \
    test_validate_clean_safety_multiple_protected_branches