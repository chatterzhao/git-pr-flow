#!/bin/bash
# Path Atomic Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/atomic/path-atomic.sh"

# 测试 path_extract_suffix
test_path_extract_suffix_e() {
    local result
    result=$(path_extract_suffix "auth-e")
    assert_equals "e" "$result" "应该提取到 -e 后缀"
}

test_path_extract_suffix_ef() {
    local result
    result=$(path_extract_suffix "auth-login-ef")
    assert_equals "ef" "$result" "应该提取到 -ef 后缀"
}

test_path_extract_suffix_none() {
    local result
    result=$(path_extract_suffix "auth")
    assert_equals "none" "$result" "没有后缀应该返回 none"
}

test_path_extract_suffix_complex() {
    local result
    result=$(path_extract_suffix "epic-auth-core-e")
    assert_equals "e" "$result" "复杂名称应该正确提取后缀"
}

# 测试 strip_suffix_from_input
test_strip_suffix_e() {
    local result
    result=$(strip_suffix_from_input "auth-e")
    assert_equals "auth" "$result" "应该移除 -e 后缀"
}

test_strip_suffix_ef() {
    local result
    result=$(strip_suffix_from_input "auth-login-ef")
    assert_equals "auth-login" "$result" "应该移除 -ef 后缀"
}

test_strip_suffix_none() {
    local result
    result=$(strip_suffix_from_input "auth")
    assert_equals "auth" "$result" "没有后缀应该保持原样"
}

# 测试 extract_prefix_from_input
test_extract_prefix_epic_dash() {
    local result
    result=$(extract_prefix_from_input "epic-auth")
    assert_equals "epic-" "$result" "应该识别 epic- 前缀"
}

test_extract_prefix_epic_underscore() {
    local result
    result=$(extract_prefix_from_input "epic_auth")
    assert_equals "epic_" "$result" "应该识别 epic_ 前缀"
}

test_extract_prefix_epic_slash() {
    local result
    result=$(extract_prefix_from_input "epic/auth")
    assert_equals "epic/" "$result" "应该识别 epic/ 前缀"
}

test_extract_prefix_none() {
    local result
    result=$(extract_prefix_from_input "auth")
    assert_equals "none" "$result" "没有前缀应该返回 none"
}

# 测试 strip_epic_prefix_from_input
test_strip_epic_prefix_dash() {
    local result
    result=$(strip_epic_prefix_from_input "epic-auth")
    assert_equals "auth" "$result" "应该移除 epic- 前缀"
}

test_strip_epic_prefix_underscore() {
    local result
    result=$(strip_epic_prefix_from_input "epic_auth")
    assert_equals "auth" "$result" "应该移除 epic_ 前缀"
}

test_strip_epic_prefix_slash() {
    local result
    result=$(strip_epic_prefix_from_input "epic/auth")
    assert_equals "auth" "$result" "应该移除 epic/ 前缀"
}

test_strip_epic_prefix_none() {
    local result
    result=$(strip_epic_prefix_from_input "auth")
    assert_equals "auth" "$result" "没有前缀应该保持原样"
}

# 测试 validate_name_format
test_validate_name_format_valid() {
    if validate_name_format "auth" 2>/dev/null; then
        assert_true "true" "auth 应该是有效名称"
    else
        assert_true "false" "auth 应该是有效名称"
    fi
}

test_validate_name_format_valid_complex() {
    if validate_name_format "auth-core-utils" 2>/dev/null; then
        assert_true "true" "auth-core-utils 应该是有效名称"
    else
        assert_true "false" "auth-core-utils 应该是有效名称"
    fi
}

test_validate_name_format_invalid_short() {
    if validate_name_format "a" 2>/dev/null; then
        assert_true "false" "单字符名称应该无效"
    else
        assert_true "true" "单字符名称应该无效"
    fi
}

test_validate_name_format_invalid_uppercase() {
    if validate_name_format "Auth" 2>/dev/null; then
        assert_true "false" "包含大写字母应该无效"
    else
        assert_true "true" "包含大写字母应该无效"
    fi
}

test_validate_name_format_invalid_special() {
    if validate_name_format "auth@core" 2>/dev/null; then
        assert_true "false" "包含特殊字符应该无效"
    else
        assert_true "true" "包含特殊字符应该无效"
    fi
}

test_validate_name_format_invalid_start_dash() {
    if validate_name_format "-auth" 2>/dev/null; then
        assert_true "false" "以连字符开头应该无效"
    else
        assert_true "true" "以连字符开头应该无效"
    fi
}

test_validate_name_format_invalid_end_dash() {
    if validate_name_format "auth-" 2>/dev/null; then
        assert_true "false" "以连字符结尾应该无效"
    else
        assert_true "true" "以连字符结尾应该无效"
    fi
}

# 测试 validate_input_suffix_matches_expected
test_validate_suffix_match_none_with_e() {
    if validate_input_suffix_matches_expected "auth" "e" 2>/dev/null; then
        assert_true "true" "没有后缀但期望e应该匹配（可自动补全）"
    else
        assert_true "false" "没有后缀但期望e应该匹配（可自动补全）"
    fi
}

test_validate_suffix_match_e_with_e() {
    if validate_input_suffix_matches_expected "auth-e" "e" 2>/dev/null; then
        assert_true "true" "后缀e期望e应该匹配"
    else
        assert_true "false" "后缀e期望e应该匹配"
    fi
}

test_validate_suffix_mismatch_ef_with_e() {
    if validate_input_suffix_matches_expected "auth-ef" "e" 2>/dev/null; then
        assert_true "false" "后缀ef期望e应该不匹配"
    else
        assert_true "true" "后缀ef期望e应该不匹配"
    fi
}

# 测试 ensure_suffix_present
test_ensure_suffix_present_add() {
    local result
    result=$(ensure_suffix_present "auth" "e")
    assert_equals "auth-e" "$result" "应该添加缺失的后缀"
}

test_ensure_suffix_present_keep() {
    local result
    result=$(ensure_suffix_present "auth-e" "e")
    assert_equals "auth-e" "$result" "已有后缀应该保持"
}

# 测试 replace_suffix_forcefully
test_replace_suffix_forcefully() {
    local result
    result=$(replace_suffix_forcefully "auth-ef" "e")
    assert_equals "auth-e" "$result" "应该强制替换后缀"
}

test_replace_suffix_forcefully_add() {
    local result
    result=$(replace_suffix_forcefully "auth" "e")
    assert_equals "auth-e" "$result" "没有后缀时应该添加"
}

# 测试 add_epic_prefix_if_missing
test_add_epic_prefix_missing() {
    local result
    result=$(add_epic_prefix_if_missing "auth")
    assert_equals "epic-auth" "$result" "应该添加缺失的前缀"
}

test_add_epic_prefix_existing() {
    local result
    result=$(add_epic_prefix_if_missing "epic-auth")
    assert_equals "epic-auth" "$result" "已有前缀应该保持"
}

test_add_epic_prefix_nonstandard() {
    local result
    result=$(add_epic_prefix_if_missing "epic_auth")
    assert_equals "epic-auth" "$result" "非标准前缀应该被替换"
}

# 运行所有测试
main() {
    init_test_framework
    
    echo "开始 Path Atomic Methods 单元测试..."
    
    local test_functions=(
        test_path_extract_suffix_e
        test_path_extract_suffix_ef
        test_path_extract_suffix_none
        test_path_extract_suffix_complex
        test_strip_suffix_e
        test_strip_suffix_ef
        test_strip_suffix_none
        test_extract_prefix_epic_dash
        test_extract_prefix_epic_underscore
        test_extract_prefix_epic_slash
        test_extract_prefix_none
        test_strip_epic_prefix_dash
        test_strip_epic_prefix_underscore
        test_strip_epic_prefix_slash
        test_strip_epic_prefix_none
        test_validate_name_format_valid
        test_validate_name_format_valid_complex
        test_validate_name_format_invalid_short
        test_validate_name_format_invalid_uppercase
        test_validate_name_format_invalid_special
        test_validate_name_format_invalid_start_dash
        test_validate_name_format_invalid_end_dash
        test_validate_suffix_match_none_with_e
        test_validate_suffix_match_e_with_e
        test_validate_suffix_mismatch_ef_with_e
        test_ensure_suffix_present_add
        test_ensure_suffix_present_keep
        test_replace_suffix_forcefully
        test_replace_suffix_forcefully_add
        test_add_epic_prefix_missing
        test_add_epic_prefix_existing
        test_add_epic_prefix_nonstandard
    )
    
    run_test_suite "Path Atomic Methods" "${test_functions[@]}"
    
    show_test_summary
    generate_test_report
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi