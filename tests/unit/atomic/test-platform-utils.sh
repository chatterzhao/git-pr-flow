#!/bin/bash
# Platform Utils Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/atomic/platform-utils.sh"

# 测试 detect_platform
test_detect_platform() {
    local result
    result=$(detect_platform)
    
    # 应该返回已知的平台类型之一
    case "$result" in
        "macos"|"linux"|"windows"|"unknown")
            assert_true "true" "应该返回有效的平台类型"
            ;;
        *)
            assert_true "false" "返回了无效的平台类型: $result"
            ;;
    esac
}

# 测试 get_path_separator
test_get_path_separator() {
    local result
    result=$(get_path_separator)
    
    # 应该返回 / 或 \
    if [[ "$result" == "/" ]] || [[ "$result" == "\\" ]]; then
        assert_true "true" "应该返回有效的路径分隔符"
    else
        assert_true "false" "返回了无效的路径分隔符: $result"
    fi
}

# 测试 is_root_path
test_is_root_path_unix() {
    if is_root_path "/"; then
        assert_true "true" "/ 应该被识别为根路径"
    else
        assert_true "false" "/ 应该被识别为根路径"
    fi
}

test_is_root_path_not_root() {
    if is_root_path "/home/user"; then
        assert_true "false" "/home/user 不应该被识别为根路径"
    else
        assert_true "true" "/home/user 不应该被识别为根路径"
    fi
}

# 测试 normalize_path_separators
test_normalize_path_separators() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            local result
            result=$(normalize_path_separators "C:/Users/test")
            assert_equals "C:\\Users\\test" "$result" "Windows应该将/转换为\\"
            ;;
        *)
            local result
            result=$(normalize_path_separators "C:\\Users\\test")
            assert_equals "C:/Users/test" "$result" "Unix应该将\\转换为/"
            ;;
    esac
}

# 测试 join_paths
test_join_paths() {
    local result
    result=$(join_paths "/home/user" "project")
    
    # 结果应该包含正确的路径分隔符
    local separator
    separator=$(get_path_separator)
    local expected="/home/user${separator}project"
    
    # 标准化比较
    local normalized_result
    local normalized_expected
    normalized_result=$(normalize_path_separators "$result")
    normalized_expected=$(normalize_path_separators "$expected")
    
    assert_equals "$normalized_expected" "$normalized_result" "路径连接应该正确"
}

test_join_paths_with_trailing_separator() {
    local separator
    separator=$(get_path_separator)
    local result
    result=$(join_paths "/home/user/" "project")
    
    local expected="/home/user${separator}project"
    local normalized_result
    local normalized_expected
    normalized_result=$(normalize_path_separators "$result")
    normalized_expected=$(normalize_path_separators "$expected")
    
    assert_equals "$normalized_expected" "$normalized_result" "应该处理尾部分隔符"
}

# 测试 path_contains
test_path_contains_true() {
    if path_contains "/home/user/.worktrees/branch" ".worktree"; then
        assert_true "true" "应该检测到路径包含.worktree"
    else
        assert_true "false" "应该检测到路径包含.worktree"
    fi
}

test_path_contains_false() {
    if path_contains "/home/user/project" ".worktree"; then
        assert_true "false" "不应该检测到路径包含.worktree"
    else
        assert_true "true" "不应该检测到路径包含.worktree"
    fi
}

# 测试 path_starts_with
test_path_starts_with_true() {
    if path_starts_with "/home/user/project/.worktrees/branch" "/home/user/project/.worktrees"; then
        assert_true "true" "应该检测到路径以指定前缀开头"
    else
        assert_true "false" "应该检测到路径以指定前缀开头"
    fi
}

test_path_starts_with_false() {
    if path_starts_with "/home/other/project" "/home/user/project"; then
        assert_true "false" "不应该检测到路径以指定前缀开头"
    else
        assert_true "true" "不应该检测到路径以指定前缀开头"
    fi
}

test_path_starts_with_partial_match() {
    # 测试部分匹配问题：/home/user-test 不应该匹配 /home/user
    if path_starts_with "/home/user-test/project" "/home/user"; then
        assert_true "false" "不应该部分匹配路径前缀"
    else
        assert_true "true" "不应该部分匹配路径前缀"
    fi
}

# 测试 get_absolute_path
test_get_absolute_path() {
    local result
    result=$(get_absolute_path ".")
    
    # 应该返回绝对路径（以/开头，在Unix-like系统上）
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            # Windows绝对路径应该包含盘符
            if [[ "$result" =~ ^[A-Za-z]: ]]; then
                assert_true "true" "Windows绝对路径应该以盘符开头"
            else
                assert_true "false" "Windows绝对路径应该以盘符开头，实际: $result"
            fi
            ;;
        *)
            # Unix-like绝对路径应该以/开头
            if [[ "$result" == /* ]]; then
                assert_true "true" "Unix绝对路径应该以/开头"
            else
                assert_true "false" "Unix绝对路径应该以/开头，实际: $result"
            fi
            ;;
    esac
}

# 测试 get_parent_directory
test_get_parent_directory() {
    local result
    result=$(get_parent_directory "/home/user/project")
    
    assert_equals "/home/user" "$result" "应该返回正确的父目录"
}

# 测试 validate_path_format
test_validate_path_format_valid() {
    if validate_path_format "/home/user/project"; then
        assert_true "true" "有效路径应该通过验证"
    else
        assert_true "false" "有效路径应该通过验证"
    fi
}

# 运行所有测试
main() {
    init_test_framework
    
    echo "开始 Platform Utils 单元测试..."
    
    local test_functions=(
        test_detect_platform
        test_get_path_separator
        test_is_root_path_unix
        test_is_root_path_not_root
        test_normalize_path_separators
        test_join_paths
        test_join_paths_with_trailing_separator
        test_path_contains_true
        test_path_contains_false
        test_path_starts_with_true
        test_path_starts_with_false
        test_path_starts_with_partial_match
        test_get_absolute_path
        test_get_parent_directory
        test_validate_path_format_valid
    )
    
    run_test_suite "Platform Utils" "${test_functions[@]}"
    
    show_test_summary
    generate_test_report
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi