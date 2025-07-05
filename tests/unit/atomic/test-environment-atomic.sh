#!/bin/bash
# Environment Atomic Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/atomic/environment-atomic.sh"

# 测试 find_project_root
test_find_project_root_with_git_dir() {
    # 在临时目录创建Git仓库结构
    mkdir -p "$TEST_TEMP_DIR/project/.git"
    mkdir -p "$TEST_TEMP_DIR/project/subdir"
    
    # 从子目录测试
    cd "$TEST_TEMP_DIR/project/subdir"
    
    local result
    result=$(find_project_root)
    local expected="$TEST_TEMP_DIR/project"
    
    assert_equals "$expected" "$result" "应该找到Git仓库根目录"
}

test_find_project_root_with_git_file() {
    # 模拟worktree的.git文件
    mkdir -p "$TEST_TEMP_DIR/project"
    echo "gitdir: /some/path/.git/worktrees/branch" > "$TEST_TEMP_DIR/project/.git"
    mkdir -p "$TEST_TEMP_DIR/project/subdir"
    
    cd "$TEST_TEMP_DIR/project/subdir"
    
    local result
    result=$(find_project_root)
    local expected="$TEST_TEMP_DIR/project"
    
    assert_equals "$expected" "$result" "应该识别worktree的.git文件"
}

test_find_project_root_no_git() {
    # 创建没有.git的目录
    mkdir -p "$TEST_TEMP_DIR/not-git-project"
    cd "$TEST_TEMP_DIR/not-git-project"
    
    if find_project_root >/dev/null 2>&1; then
        assert_true "false" "没有Git仓库应该返回失败"
    else
        assert_true "true" "没有Git仓库应该返回失败"
    fi
}

test_find_project_root_nested_git() {
    # 创建嵌套Git仓库，应该找到最近的
    mkdir -p "$TEST_TEMP_DIR/outer/.git"
    mkdir -p "$TEST_TEMP_DIR/outer/inner/.git"
    mkdir -p "$TEST_TEMP_DIR/outer/inner/deep"
    
    cd "$TEST_TEMP_DIR/outer/inner/deep"
    
    local result
    result=$(find_project_root)
    local expected="$TEST_TEMP_DIR/outer/inner"
    
    assert_equals "$expected" "$result" "应该找到最近的Git仓库"
}

# 测试 determine_environment_type
test_determine_environment_type_root() {
    local project_root="/path/to/project"
    local current_path="/path/to/project"
    
    local result
    result=$(determine_environment_type "$current_path" "$project_root")
    
    assert_equals "root" "$result" "项目根目录应该识别为root"
}

test_determine_environment_type_epic() {
    local project_root="/path/to/project"
    local current_path="/path/to/project/.worktrees/epic-auth-e"
    
    local result
    result=$(determine_environment_type "$current_path" "$project_root")
    
    assert_equals "epic" "$result" "Epic worktree应该识别为epic"
}

test_determine_environment_type_feature() {
    local project_root="/path/to/project"
    local current_path="/path/to/project/.worktrees/epic-auth-e-login-ef"
    
    local result
    result=$(determine_environment_type "$current_path" "$project_root")
    
    assert_equals "feature" "$result" "Feature worktree应该识别为feature"
}

test_determine_environment_type_unknown_worktree() {
    local project_root="/path/to/project"
    local current_path="/path/to/project/.worktrees/some-branch"
    
    local result
    result=$(determine_environment_type "$current_path" "$project_root")
    
    assert_equals "unknown" "$result" "非标准worktree应该识别为unknown"
}

test_determine_environment_type_unknown_path() {
    local project_root="/path/to/project"
    local current_path="/some/other/path"
    
    local result
    result=$(determine_environment_type "$current_path" "$project_root")
    
    assert_equals "unknown" "$result" "项目外路径应该识别为unknown"
}

# 测试 extract_worktree_name
test_extract_worktree_name() {
    local worktree_path="/path/to/project/.worktrees/epic-auth-e"
    local project_root="/path/to/project"
    
    local result
    result=$(extract_worktree_name "$worktree_path" "$project_root")
    
    assert_equals "epic-auth-e" "$result" "应该正确提取worktree名称"
}

# 测试 extract_epic_environment (需要mock git命令)
test_extract_epic_environment() {
    # Mock git命令
    mock_command "git" "epic-auth-e"
    
    local current_path="/path/to/project/.worktrees/epic-auth-e"
    local project_root="/path/to/project"
    
    local result
    result=$(extract_epic_environment "$current_path" "$project_root")
    
    # 验证JSON结构
    assert_contains "$result" '"type": "epic"' "应该包含type字段"
    assert_contains "$result" '"epic_name": "auth"' "应该包含正确的epic名称"
    assert_contains "$result" '"git_branch": "epic-auth-e"' "应该包含git分支名"
}

# 测试 extract_feature_environment
test_extract_feature_environment() {
    # Mock git命令
    mock_command "git" "epic-auth-e-login-ef"
    
    local current_path="/path/to/project/.worktrees/epic-auth-e-login-ef"
    local project_root="/path/to/project"
    
    local result
    result=$(extract_feature_environment "$current_path" "$project_root")
    
    # 验证JSON结构
    assert_contains "$result" '"type": "feature"' "应该包含type字段"
    assert_contains "$result" '"epic_name": "auth"' "应该包含正确的epic名称"
    assert_contains "$result" '"feature_name": "login"' "应该包含正确的feature名称"
    assert_contains "$result" '"git_branch": "epic-auth-e-login-ef"' "应该包含git分支名"
}

# 测试 extract_root_environment
test_extract_root_environment() {
    # Mock git命令
    mock_command "git" "develop"
    
    local current_path="/path/to/project"
    local project_root="/path/to/project"
    
    local result
    result=$(extract_root_environment "$current_path" "$project_root")
    
    # 验证JSON结构
    assert_contains "$result" '"type": "root"' "应该包含type字段"
    assert_contains "$result" '"epic_name": null' "epic_name应该为null"
    assert_contains "$result" '"feature_name": null' "feature_name应该为null"
    assert_contains "$result" '"git_branch": "develop"' "应该包含git分支名"
}

# 测试 extract_unknown_environment
test_extract_unknown_environment() {
    # Mock git命令
    mock_command "git" "some-branch"
    
    local current_path="/some/other/path"
    local project_root="/path/to/project"
    
    local result
    result=$(extract_unknown_environment "$current_path" "$project_root")
    
    # 验证JSON结构
    assert_contains "$result" '"type": "unknown"' "应该包含type字段"
    assert_contains "$result" '"epic_name": null' "epic_name应该为null"
    assert_contains "$result" '"feature_name": null' "feature_name应该为null"
    assert_contains "$result" '"git_branch": "some-branch"' "应该包含git分支名"
}

# 运行所有测试
main() {
    init_test_framework
    
    echo "开始 Environment Atomic Methods 单元测试..."
    
    local test_functions=(
        test_find_project_root_with_git_dir
        test_find_project_root_with_git_file
        test_find_project_root_no_git
        test_find_project_root_nested_git
        test_determine_environment_type_root
        test_determine_environment_type_epic
        test_determine_environment_type_feature
        test_determine_environment_type_unknown_worktree
        test_determine_environment_type_unknown_path
        test_extract_worktree_name
        test_extract_epic_environment
        test_extract_feature_environment
        test_extract_root_environment
        test_extract_unknown_environment
    )
    
    run_test_suite "Environment Atomic Methods" "${test_functions[@]}"
    
    show_test_summary
    generate_test_report
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi