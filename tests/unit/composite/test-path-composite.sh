#!/bin/bash
# Path Composite Methods Unit Tests

set -euo pipefail

# 导入测试框架和被测试模块
source "$(dirname "$0")/../../test-framework.sh"
source "$(dirname "$0")/../../../lib/core/composite/path-composite.sh"

# 测试 intelligent_parse_user_intent
test_intelligent_parse_user_intent_epic() {
    local result
    result=$(intelligent_parse_user_intent "auth" "epic")
    
    # 检查JSON结构正确性
    assert_contains "$result" '"detected_type": "epic"' "应该检测为epic类型"
    assert_contains "$result" '"epic_name": "auth"' "应该解析出epic名称"
    assert_contains "$result" '"suffix": "none"' "应该检测到无后缀"
}

test_intelligent_parse_user_intent_feature() {
    local result
    result=$(intelligent_parse_user_intent "auth-login-ef" "auto")
    
    assert_contains "$result" '"detected_type": "feature"' "应该检测为feature类型"
    assert_contains "$result" '"suffix": "ef"' "应该检测到ef后缀"
}

test_intelligent_parse_user_intent_with_prefix() {
    local result
    result=$(intelligent_parse_user_intent "epic-auth-e" "auto")
    
    assert_contains "$result" '"detected_type": "epic"' "应该检测为epic类型"
    assert_contains "$result" '"epic_name": "auth"' "应该解析出清洁的epic名称"
    assert_contains "$result" '"prefix": "epic-"' "应该检测到epic前缀"
}

# 测试 normalize_and_validate_input
test_normalize_and_validate_input_epic() {
    local result
    result=$(normalize_and_validate_input "auth" "epic")
    
    assert_equals 0 $? "epic输入验证应该成功"
    assert_contains "$result" '"type": "epic"' "应该返回epic类型"
    assert_contains "$result" '"epic_name": "auth"' "应该返回epic名称"
    assert_contains "$result" '"validated": true' "应该标记为已验证"
}

test_normalize_and_validate_input_feature() {
    local result
    result=$(normalize_and_validate_input "auth-login" "feature")
    
    assert_equals 0 $? "feature输入验证应该成功"
    assert_contains "$result" '"type": "feature"' "应该返回feature类型"
    assert_contains "$result" '"epic_name": "auth"' "应该返回epic名称"
    assert_contains "$result" '"feature_name": "login"' "应该返回feature名称"
}

test_normalize_and_validate_input_invalid_name() {
    local result
    result=$(normalize_and_validate_input "auth@invalid" "epic" 2>/dev/null)
    
    assert_not_equals 0 $? "无效字符应该导致验证失败"
}

# 测试 build_standard_branch_names
test_build_standard_branch_names_epic() {
    local result
    result=$(build_standard_branch_names "auth")
    
    assert_equals "epic-auth-e" "$result" "应该生成标准epic分支名"
}

test_build_standard_branch_names_feature() {
    local result
    result=$(build_standard_branch_names "auth" "login")
    
    assert_equals "epic-auth-e-login-ef" "$result" "应该生成标准feature分支名"
}

# 测试 generate_all_standard_names
test_generate_all_standard_names_epic() {
    local result
    result=$(generate_all_standard_names "auth")
    
    assert_contains "$result" '"epic_branch": "epic-auth-e"' "应该生成epic分支名"
    assert_contains "$result" '"feature_branch": ""' "feature分支应该为空"
    assert_contains "$result" '"worktree_path": ".worktrees/epic-auth-e"' "应该生成worktree路径"
}

test_generate_all_standard_names_feature() {
    local result
    result=$(generate_all_standard_names "auth" "login")
    
    assert_contains "$result" '"epic_branch": "epic-auth-e"' "应该生成epic分支名"
    assert_contains "$result" '"feature_branch": "epic-auth-e-login-ef"' "应该生成feature分支名"
    assert_contains "$result" '"worktree_path": ".worktrees/epic-auth-e-login-ef"' "应该生成feature worktree路径"
}

# 测试 path_complete_processing
test_path_complete_processing_epic() {
    # 需要在测试环境中
    if [[ -d ".git" ]]; then
        local result
        result=$(path_complete_processing "auth" "epic" "$(pwd)")
        
        assert_equals 0 $? "完整路径处理应该成功"
        assert_contains "$result" '"success": true' "应该标记为成功"
        assert_contains "$result" '"type": "epic"' "应该返回正确类型"
    else
        test_skip "需要Git环境"
    fi
}

# 测试 intelligent_path_transformation
test_intelligent_path_transformation_epic_to_feature() {
    local result
    result=$(intelligent_path_transformation "epic-auth-e" "feature")
    
    assert_equals "epic-auth-ef" "$result" "应该正确转换为feature路径"
}

test_intelligent_path_transformation_feature_to_epic() {
    local result
    result=$(intelligent_path_transformation "epic-auth-login-ef" "epic")
    
    assert_equals "epic-auth-login-e" "$result" "应该正确转换为epic路径"
}

# 错误处理测试
test_normalize_and_validate_input_type_mismatch() {
    local result
    result=$(normalize_and_validate_input "auth-login-ef" "epic" 2>/dev/null)
    
    assert_not_equals 0 $? "类型不匹配应该导致失败"
}

test_normalize_and_validate_input_empty_epic() {
    local result
    result=$(normalize_and_validate_input "" "epic" 2>/dev/null)
    
    assert_not_equals 0 $? "空输入应该导致失败"
}

# 边缘情况测试
test_intelligent_parse_complex_feature_name() {
    local result
    result=$(intelligent_parse_user_intent "auth-e-login-register-ef" "auto")
    
    assert_contains "$result" '"detected_type": "feature"' "应该正确解析复杂feature名称"
}

test_normalize_special_characters() {
    local result
    result=$(normalize_and_validate_input "auth_core-test" "epic" 2>/dev/null)
    
    assert_equals 0 $? "包含下划线的名称应该有效"
}

# 运行所有测试
run_test_suite "Path Composite Tests" \
    test_intelligent_parse_user_intent_epic \
    test_intelligent_parse_user_intent_feature \
    test_intelligent_parse_user_intent_with_prefix \
    test_normalize_and_validate_input_epic \
    test_normalize_and_validate_input_feature \
    test_normalize_and_validate_input_invalid_name \
    test_build_standard_branch_names_epic \
    test_build_standard_branch_names_feature \
    test_generate_all_standard_names_epic \
    test_generate_all_standard_names_feature \
    test_path_complete_processing_epic \
    test_intelligent_path_transformation_epic_to_feature \
    test_intelligent_path_transformation_feature_to_epic \
    test_normalize_and_validate_input_type_mismatch \
    test_normalize_and_validate_input_empty_epic \
    test_intelligent_parse_complex_feature_name \
    test_normalize_special_characters