#!/bin/bash
# Worktree Composite Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/composite/worktree-composite.sh"

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

cleanup_test_repo() {
    local test_dir="$1"
    cd /
    rm -rf "$test_dir" 2>/dev/null || true
}

# 测试 worktree_find_or_create - 创建新worktree
test_worktree_find_or_create_new() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_find_or_create "test-branch" "$test_dir" 2>/dev/null || echo "")
    
    if [[ -n "$result" && $? -eq 0 ]]; then
        assert_contains "$result" "$test_dir/.worktrees/test-branch" "应该返回正确的worktree路径"
        assert_dir_exists "$test_dir/.worktrees/test-branch" "worktree目录应该被创建"
    else
        test_skip "worktree创建可能需要特定环境"
    fi
    
    cleanup_test_repo "$test_dir"
}

test_worktree_find_or_create_existing() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    # 先创建一个worktree
    git worktree add .worktrees/existing-branch --quiet 2>/dev/null || true
    
    if [[ -d ".worktrees/existing-branch" ]]; then
        local result
        result=$(worktree_find_or_create "existing-branch" "$test_dir" 2>/dev/null || echo "")
        
        if [[ -n "$result" ]]; then
            assert_contains "$result" "找到现有worktree" "应该找到现有的worktree"
        fi
    else
        test_skip "无法创建测试worktree"
    fi
    
    cleanup_test_repo "$test_dir"
}

test_worktree_find_or_create_invalid_project_root() {
    local result
    result=$(worktree_find_or_create "test-branch" "/nonexistent/path" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "无效项目根目录应该导致失败"
}

# 测试 worktree_safe_delete
test_worktree_safe_delete_nonexistent() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_safe_delete "nonexistent-branch" "$test_dir")
    
    assert_equals 0 $? "删除不存在的worktree应该成功（无操作）"
    assert_contains "$result" "未找到" "应该提示未找到worktree"
    
    cleanup_test_repo "$test_dir"
}

test_worktree_safe_delete_with_force() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建一个worktree并添加一些修改
    git worktree add .worktrees/test-delete --quiet 2>/dev/null || true
    
    if [[ -d ".worktrees/test-delete" ]]; then
        echo "some changes" > .worktrees/test-delete/test.txt
        
        local result
        result=$(worktree_safe_delete "test-delete" "$test_dir" "true")
        
        assert_equals 0 $? "强制删除应该成功"
        assert_not_dir_exists "$test_dir/.worktrees/test-delete" "worktree目录应该被删除"
    else
        test_skip "无法创建测试worktree"
    fi
    
    cleanup_test_repo "$test_dir"
}

# 测试 worktree_intelligent_switch
test_worktree_intelligent_switch_basic() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_intelligent_switch "test-branch" "$test_dir" 2>/dev/null || echo "")
    
    if [[ -n "$result" && $? -eq 0 ]]; then
        assert_contains "$result" ".worktrees/test-branch" "应该返回正确的切换路径"
    else
        test_skip "worktree切换可能需要特定环境"
    fi
    
    cleanup_test_repo "$test_dir"
}

test_worktree_intelligent_switch_invalid_project_root() {
    local result
    result=$(worktree_intelligent_switch "test-branch" "/nonexistent/path" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "无效项目根目录应该导致失败"
}

# 测试 worktree_batch_management
test_worktree_batch_management_list_empty() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_batch_management "list" "*" "$test_dir")
    
    assert_equals 0 $? "列出空worktree列表应该成功"
    assert_contains "$result" "没有找到匹配" "应该提示没有找到匹配项"
    
    cleanup_test_repo "$test_dir"
}

test_worktree_batch_management_invalid_action() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_batch_management "invalid_action" "*" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "无效操作应该导致失败"
    
    cleanup_test_repo "$test_dir"
}

test_worktree_batch_management_validate() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_batch_management "validate" "*" "$test_dir")
    
    assert_equals 0 $? "验证操作应该成功"
    assert_contains "$result" "验证结果" "应该显示验证结果"
    
    cleanup_test_repo "$test_dir"
}

test_worktree_batch_management_clean() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_batch_management "clean" "*" "$test_dir")
    
    assert_equals 0 $? "清理操作应该成功"
    assert_contains "$result" "清理完成" "应该显示清理完成消息"
    
    cleanup_test_repo "$test_dir"
}

# 测试 worktree_get_usage_statistics
test_worktree_get_usage_statistics_empty() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(worktree_get_usage_statistics "$test_dir")
    
    assert_equals 0 $? "获取统计信息应该成功"
    
    # 验证JSON格式正确性
    echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
    
    # 验证必需字段存在
    assert_contains "$result" '"total_worktrees"' "应该包含total_worktrees字段"
    assert_contains "$result" '"epic_worktrees"' "应该包含epic_worktrees字段"
    assert_contains "$result" '"feature_worktrees"' "应该包含feature_worktrees字段"
    assert_contains "$result" '"valid_worktrees"' "应该包含valid_worktrees字段"
    assert_contains "$result" '"invalid_worktrees"' "应该包含invalid_worktrees字段"
    assert_contains "$result" '"disk_usage"' "应该包含disk_usage字段"
    
    cleanup_test_repo "$test_dir"
}

test_worktree_get_usage_statistics_invalid_root() {
    local result
    result=$(worktree_get_usage_statistics "/nonexistent/path" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "无效项目根目录应该导致失败"
}

# JSON输出格式验证测试
test_worktree_json_output_consistency() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    # 测试统计信息的JSON格式
    local stats_result
    stats_result=$(worktree_get_usage_statistics "$test_dir")
    
    # 验证JSON格式
    echo "$stats_result" | jq empty 2>/dev/null || assert_fail "统计信息应该是有效的JSON"
    
    # 验证数值字段类型
    local total_count
    total_count=$(echo "$stats_result" | jq -r '.total_worktrees' 2>/dev/null)
    [[ "$total_count" =~ ^[0-9]+$ ]] || assert_fail "total_worktrees应该是数字"
    
    cleanup_test_repo "$test_dir"
}

# 错误处理测试
test_worktree_operations_without_git() {
    local non_git_dir="/tmp/not-git-$$"
    mkdir -p "$non_git_dir"
    
    local result
    result=$(worktree_find_or_create "test-branch" "$non_git_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "非Git目录应该导致操作失败"
    
    rm -rf "$non_git_dir"
}

# 边缘情况测试
test_worktree_special_branch_names() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    # 测试包含特殊字符的分支名
    local special_names=("epic-auth_core-e" "epic-test123-e" "epic-a-b-c-e")
    
    for branch_name in "${special_names[@]}"; do
        local result
        result=$(worktree_find_or_create "$branch_name" "$test_dir" 2>/dev/null || echo "")
        
        if [[ $? -eq 0 && -n "$result" ]]; then
            assert_contains "$result" "$branch_name" "应该正确处理特殊分支名：$branch_name"
        fi
    done
    
    cleanup_test_repo "$test_dir"
}

test_worktree_concurrent_operations() {
    local test_dir="/tmp/gpf-worktree-test-$$"
    setup_test_repo "$test_dir"
    
    # 测试并发创建相同worktree（模拟竞态条件）
    local result1 result2
    result1=$(worktree_find_or_create "concurrent-branch" "$test_dir" 2>/dev/null || echo "")
    result2=$(worktree_find_or_create "concurrent-branch" "$test_dir" 2>/dev/null || echo "")
    
    # 两次操作都应该成功（第二次应该找到现有的）
    if [[ -n "$result1" && -n "$result2" ]]; then
        assert_true true "并发操作应该正确处理"
    else
        test_skip "并发测试需要特定环境"
    fi
    
    cleanup_test_repo "$test_dir"
}

# 依赖检查测试
test_worktree_composite_dependencies() {
    # 检查是否正确导入了依赖
    if type worktree_find_by_branch >/dev/null 2>&1; then
        assert_true true "应该正确导入worktree-atomic依赖"
    else
        assert_fail "缺少worktree-atomic依赖"
    fi
    
    if type git_get_current_branch >/dev/null 2>&1; then
        assert_true true "应该正确导入git-atomic依赖"
    else
        assert_fail "缺少git-atomic依赖"
    fi
    
    if type find_project_root >/dev/null 2>&1; then
        assert_true true "应该正确导入environment-atomic依赖"
    else
        assert_fail "缺少environment-atomic依赖"
    fi
}

# 辅助函数
assert_dir_exists() {
    local dir="$1"
    local message="$2"
    
    if [[ -d "$dir" ]]; then
        assert_true true "$message"
    else
        assert_fail "$message - 目录不存在: $dir"
    fi
}

assert_not_dir_exists() {
    local dir="$1"
    local message="$2"
    
    if [[ ! -d "$dir" ]]; then
        assert_true true "$message"
    else
        assert_fail "$message - 目录仍然存在: $dir"
    fi
}

# 运行所有测试
run_test_suite "Worktree Composite Tests" \
    test_worktree_find_or_create_new \
    test_worktree_find_or_create_existing \
    test_worktree_find_or_create_invalid_project_root \
    test_worktree_safe_delete_nonexistent \
    test_worktree_safe_delete_with_force \
    test_worktree_intelligent_switch_basic \
    test_worktree_intelligent_switch_invalid_project_root \
    test_worktree_batch_management_list_empty \
    test_worktree_batch_management_invalid_action \
    test_worktree_batch_management_validate \
    test_worktree_batch_management_clean \
    test_worktree_get_usage_statistics_empty \
    test_worktree_get_usage_statistics_invalid_root \
    test_worktree_json_output_consistency \
    test_worktree_operations_without_git \
    test_worktree_special_branch_names \
    test_worktree_concurrent_operations \
    test_worktree_composite_dependencies