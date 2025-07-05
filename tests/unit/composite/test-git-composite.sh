#!/bin/bash
# Git Composite Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/composite/git-composite.sh"

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
    rm -rf "$test_dir"
}

# 测试 git_validate_branch_state
test_git_validate_branch_state_clean() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_validate_branch_state "main" "$test_dir")
    
    assert_equals 0 $? "干净的分支状态验证应该成功"
    assert_contains "$result" '"branch": "main"' "应该包含分支名称"
    assert_contains "$result" '"working_tree_clean": true' "工作区应该是干净的"
    assert_contains "$result" '"staging_area_clean": true' "暂存区应该是干净的"
    
    cleanup_test_repo "$test_dir"
}

test_git_validate_branch_state_with_changes() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建未保存的修改
    echo "some changes" >> README.md
    
    local result
    result=$(git_validate_branch_state "main" "$test_dir")
    
    assert_equals 0 $? "有修改的分支状态验证也应该成功"
    assert_contains "$result" '"working_tree_clean": false' "工作区应该是不干净的"
    
    cleanup_test_repo "$test_dir"
}

test_git_validate_branch_state_with_staged_changes() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建暂存的修改
    echo "staged changes" > new_file.txt
    git add new_file.txt
    
    local result
    result=$(git_validate_branch_state "main" "$test_dir")
    
    assert_equals 0 $? "有暂存修改的分支状态验证应该成功"
    assert_contains "$result" '"staging_area_clean": false' "暂存区应该是不干净的"
    
    cleanup_test_repo "$test_dir"
}

test_git_validate_branch_state_wrong_branch() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_validate_branch_state "nonexistent" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "错误的分支名应该导致验证失败"
    
    cleanup_test_repo "$test_dir"
}

# 测试 git_ensure_safe_state
test_git_ensure_safe_state_switch_clean() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_ensure_safe_state "switch" "$test_dir")
    
    assert_equals 0 $? "干净状态下的切换操作应该安全"
    assert_contains "$result" "安全检查通过" "应该显示安全检查通过消息"
    
    cleanup_test_repo "$test_dir"
}

test_git_ensure_safe_state_switch_with_changes() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建未保存的修改
    echo "unsafe changes" >> README.md
    
    local result
    result=$(git_ensure_safe_state "switch" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "有未保存修改时切换操作应该不安全"
    
    cleanup_test_repo "$test_dir"
}

test_git_ensure_safe_state_merge_clean() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_ensure_safe_state "merge" "$test_dir")
    
    assert_equals 0 $? "干净状态下的合并操作应该安全"
    
    cleanup_test_repo "$test_dir"
}

test_git_ensure_safe_state_invalid_operation() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_ensure_safe_state "invalid_op" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "无效操作类型应该返回错误"
    
    cleanup_test_repo "$test_dir"
}

# 测试 git_prepare_for_operation
test_git_prepare_for_operation_clean() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_prepare_for_operation "$test_dir" 2>/dev/null || echo "")
    
    # 在没有remote的情况下，操作会部分成功
    if [[ -n "$result" ]]; then
        assert_contains "$result" "拉取远程更新" "应该尝试拉取远程更新"
    else
        test_skip "需要完整的Git remote环境"
    fi
    
    cleanup_test_repo "$test_dir"
}

# 测试 git_intelligent_branch_switch
test_git_intelligent_branch_switch_same_branch() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_intelligent_branch_switch "main" "$test_dir")
    
    assert_equals 0 $? "切换到相同分支应该成功"
    assert_contains "$result" "已在目标分支" "应该提示已在目标分支"
    
    cleanup_test_repo "$test_dir"
}

test_git_intelligent_branch_switch_new_branch() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_intelligent_branch_switch "new-branch" "$test_dir")
    
    assert_equals 0 $? "切换到新分支应该成功"
    assert_contains "$result" "创建新分支" "应该提示创建新分支"
    
    cleanup_test_repo "$test_dir"
}

# 测试 git_check_merge_status
test_git_check_merge_status_basic() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    # 创建两个分支用于测试
    git checkout -b feature-branch --quiet
    echo "feature change" > feature.txt
    git add feature.txt
    git commit -m "Feature change" --quiet
    
    git checkout main --quiet
    
    local result
    result=$(git_check_merge_status "feature-branch" "main" "$test_dir")
    
    assert_equals 0 $? "合并状态检查应该成功"
    assert_contains "$result" '"source_branch": "feature-branch"' "应该包含源分支"
    assert_contains "$result" '"target_branch": "main"' "应该包含目标分支"
    assert_contains "$result" '"ahead_count"' "应该包含领先提交数"
    
    cleanup_test_repo "$test_dir"
}

test_git_check_merge_status_nonexistent_source() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_check_merge_status "nonexistent" "main" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "不存在的源分支应该导致失败"
    
    cleanup_test_repo "$test_dir"
}

# 测试 git_check_safe_branch_deletion
test_git_check_safe_branch_deletion_current_branch() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_check_safe_branch_deletion "main" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "不能删除当前分支"
    
    cleanup_test_repo "$test_dir"
}

test_git_check_safe_branch_deletion_nonexistent() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_check_safe_branch_deletion "nonexistent" "$test_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "不存在的分支应该导致失败"
    
    cleanup_test_repo "$test_dir"
}

# JSON输出格式测试
test_json_output_git_validate_branch_state() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    local result
    result=$(git_validate_branch_state "main" "$test_dir")
    
    # 验证JSON格式正确性
    echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
    
    # 验证必需字段存在
    assert_contains "$result" '"branch"' "应该包含branch字段"
    assert_contains "$result" '"working_tree_clean"' "应该包含working_tree_clean字段"
    assert_contains "$result" '"staging_area_clean"' "应该包含staging_area_clean字段"
    assert_contains "$result" '"remote_exists"' "应该包含remote_exists字段"
    
    cleanup_test_repo "$test_dir"
}

test_json_output_git_check_merge_status() {
    local test_dir="/tmp/gpf-git-test-$$"
    setup_test_repo "$test_dir"
    
    git checkout -b test-branch --quiet
    git checkout main --quiet
    
    local result
    result=$(git_check_merge_status "test-branch" "main" "$test_dir")
    
    # 验证JSON格式正确性
    echo "$result" | jq empty 2>/dev/null || assert_fail "输出应该是有效的JSON"
    
    # 验证必需字段存在
    assert_contains "$result" '"source_branch"' "应该包含source_branch字段"
    assert_contains "$result" '"target_branch"' "应该包含target_branch字段"
    assert_contains "$result" '"is_merged"' "应该包含is_merged字段"
    assert_contains "$result" '"can_merge"' "应该包含can_merge字段"
    
    cleanup_test_repo "$test_dir"
}

# 错误处理测试
test_git_operations_invalid_repo() {
    local invalid_dir="/tmp/not-a-git-repo-$$"
    mkdir -p "$invalid_dir"
    
    local result
    result=$(git_validate_branch_state "main" "$invalid_dir" 2>/dev/null || echo "")
    
    assert_not_equals 0 $? "无效Git仓库应该导致失败"
    
    rm -rf "$invalid_dir"
}

# 运行所有测试
run_test_suite "Git Composite Tests" \
    test_git_validate_branch_state_clean \
    test_git_validate_branch_state_with_changes \
    test_git_validate_branch_state_with_staged_changes \
    test_git_validate_branch_state_wrong_branch \
    test_git_ensure_safe_state_switch_clean \
    test_git_ensure_safe_state_switch_with_changes \
    test_git_ensure_safe_state_merge_clean \
    test_git_ensure_safe_state_invalid_operation \
    test_git_prepare_for_operation_clean \
    test_git_intelligent_branch_switch_same_branch \
    test_git_intelligent_branch_switch_new_branch \
    test_git_check_merge_status_basic \
    test_git_check_merge_status_nonexistent_source \
    test_git_check_safe_branch_deletion_current_branch \
    test_git_check_safe_branch_deletion_nonexistent \
    test_json_output_git_validate_branch_state \
    test_json_output_git_check_merge_status \
    test_git_operations_invalid_repo