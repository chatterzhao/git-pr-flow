#!/bin/bash
# GPF Core - Environment Composite Methods Tests
# 测试 environment-composite.sh 中的所有组合方法

set -euo pipefail

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/../../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/core/composite/environment-composite.sh"

# 测试：environment_detect_complete
test_environment_detect_complete() {
    print_test_header "测试 environment_detect_complete - 完整环境检测"
    
    local detection_result
    detection_result=$(environment_detect_complete)
    
    # 验证JSON格式
    if echo "$detection_result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=(
        "timestamp" "platform" "git" "github" 
        "project" "environment" "shell" "capabilities" "compatibility"
    )
    
    for field in "${required_fields[@]}"; do
        if echo "$detection_result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证capabilities字段
    local capability_fields=("git_available" "gh_available" "jq_available" "curl_available")
    for field in "${capability_fields[@]}"; do
        if echo "$detection_result" | jq -e ".capabilities | has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ capabilities包含字段：$field"
        else
            echo "❌ capabilities缺少字段：$field"
            return 1
        fi
    done
    
    # 验证compatibility字段
    local compatibility_fields=("bash_version" "bash_compatible" "platform_supported")
    for field in "${compatibility_fields[@]}"; do
        if echo "$detection_result" | jq -e ".compatibility | has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ compatibility包含字段：$field"
        else
            echo "❌ compatibility缺少字段：$field"
            return 1
        fi
    done
    
    # 验证布尔值字段
    local boolean_fields=(
        ".capabilities.git_available"
        ".capabilities.gh_available"
        ".capabilities.jq_available"
        ".capabilities.curl_available"
        ".compatibility.bash_compatible"
        ".compatibility.platform_supported"
        ".project.is_gpf_project"
    )
    
    for field in "${boolean_fields[@]}"; do
        local value
        value=$(echo "$detection_result" | jq -r "$field")
        if [[ "$value" == "true" || "$value" == "false" ]]; then
            echo "✅ $field 为有效布尔值"
        else
            echo "❌ $field 不是有效布尔值：$value"
            return 1
        fi
    done
    
    # 验证时间戳格式
    local timestamp
    timestamp=$(echo "$detection_result" | jq -r '.timestamp')
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        echo "✅ 时间戳格式正确"
    else
        echo "❌ 时间戳格式错误：$timestamp"
        return 1
    fi
}

# 测试：environment_check_compatibility
test_environment_check_compatibility() {
    print_test_header "测试 environment_check_compatibility - 环境兼容性检查"
    
    # 兼容性检查应该根据当前环境返回结果
    if environment_check_compatibility; then
        echo "✅ 环境兼容性检查返回兼容（当前环境支持GPF）"
    else
        echo "⚠️ 环境兼容性检查返回不兼容（当前环境可能缺少某些依赖）"
    fi
    
    # 兼容性检查应该与detect_complete的结果一致
    local detection_result
    detection_result=$(environment_detect_complete)
    
    local git_available jq_available bash_compatible platform_supported
    git_available=$(echo "$detection_result" | jq -r '.capabilities.git_available')
    jq_available=$(echo "$detection_result" | jq -r '.capabilities.jq_available')
    bash_compatible=$(echo "$detection_result" | jq -r '.compatibility.bash_compatible')
    platform_supported=$(echo "$detection_result" | jq -r '.compatibility.platform_supported')
    
    local should_be_compatible=true
    if [[ "$git_available" == "false" || "$jq_available" == "false" || "$bash_compatible" == "false" || "$platform_supported" == "false" ]]; then
        should_be_compatible=false
    fi
    
    if environment_check_compatibility; then
        if [[ "$should_be_compatible" == "true" ]]; then
            echo "✅ 兼容性检查结果与环境检测一致（兼容）"
        else
            echo "❌ 兼容性检查结果与环境检测不一致（应该不兼容）"
            return 1
        fi
    else
        if [[ "$should_be_compatible" == "false" ]]; then
            echo "✅ 兼容性检查结果与环境检测一致（不兼容）"
        else
            echo "❌ 兼容性检查结果与环境检测不一致（应该兼容）"
            return 1
        fi
    fi
}

# 测试：environment_get_issues
test_environment_get_issues() {
    print_test_header "测试 environment_get_issues - 获取环境问题报告"
    
    local issues_result
    issues_result=$(environment_get_issues)
    
    # 验证JSON格式
    if echo "$issues_result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("has_issues" "has_warnings" "issues" "warnings" "compatible")
    for field in "${required_fields[@]}"; do
        if echo "$issues_result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证布尔字段
    local boolean_fields=("has_issues" "has_warnings" "compatible")
    for field in "${boolean_fields[@]}"; do
        local value
        value=$(echo "$issues_result" | jq -r ".$field")
        if [[ "$value" == "true" || "$value" == "false" ]]; then
            echo "✅ $field 为有效布尔值"
        else
            echo "❌ $field 不是有效布尔值：$value"
            return 1
        fi
    done
    
    # 验证数组字段
    local array_fields=("issues" "warnings")
    for field in "${array_fields[@]}"; do
        if echo "$issues_result" | jq -e ".$field | type == \"array\"" >/dev/null 2>&1; then
            echo "✅ $field 为有效数组"
        else
            echo "❌ $field 不是有效数组"
            return 1
        fi
    done
    
    # 验证逻辑一致性
    local has_issues issues_count has_warnings warnings_count
    has_issues=$(echo "$issues_result" | jq -r '.has_issues')
    issues_count=$(echo "$issues_result" | jq -r '.issues | length')
    has_warnings=$(echo "$issues_result" | jq -r '.has_warnings')
    warnings_count=$(echo "$issues_result" | jq -r '.warnings | length')
    
    if [[ "$has_issues" == "true" && "$issues_count" == "0" ]]; then
        echo "❌ 逻辑错误：has_issues为true但issues数组为空"
        return 1
    elif [[ "$has_issues" == "false" && "$issues_count" != "0" ]]; then
        echo "❌ 逻辑错误：has_issues为false但issues数组非空"
        return 1
    else
        echo "✅ has_issues逻辑一致"
    fi
    
    if [[ "$has_warnings" == "true" && "$warnings_count" == "0" ]]; then
        echo "❌ 逻辑错误：has_warnings为true但warnings数组为空"
        return 1
    elif [[ "$has_warnings" == "false" && "$warnings_count" != "0" ]]; then
        echo "❌ 逻辑错误：has_warnings为false但warnings数组非空"
        return 1
    else
        echo "✅ has_warnings逻辑一致"
    fi
    
    # 验证与兼容性检查的一致性
    local compatible
    compatible=$(echo "$issues_result" | jq -r '.compatible')
    
    if environment_check_compatibility; then
        if [[ "$compatible" == "true" ]]; then
            echo "✅ 问题报告与兼容性检查一致（兼容）"
        else
            echo "❌ 问题报告与兼容性检查不一致（应该兼容）"
            return 1
        fi
    else
        if [[ "$compatible" == "false" ]]; then
            echo "✅ 问题报告与兼容性检查一致（不兼容）"
        else
            echo "❌ 问题报告与兼容性检查不一致（应该不兼容）"
            return 1
        fi
    fi
}

# 测试：environment_get_summary
test_environment_get_summary() {
    print_test_header "测试 environment_get_summary - 获取环境摘要"
    
    local summary_result
    summary_result=$(environment_get_summary)
    
    # 验证JSON格式
    if echo "$summary_result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=(
        "platform" "git_version" "github_cli_version" 
        "is_gpf_project" "compatible" "issues_count" "warnings_count"
    )
    
    for field in "${required_fields[@]}"; do
        if echo "$summary_result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证布尔字段
    local boolean_fields=("is_gpf_project" "compatible")
    for field in "${boolean_fields[@]}"; do
        local value
        value=$(echo "$summary_result" | jq -r ".$field")
        if [[ "$value" == "true" || "$value" == "false" ]]; then
            echo "✅ $field 为有效布尔值"
        else
            echo "❌ $field 不是有效布尔值：$value"
            return 1
        fi
    done
    
    # 验证数字字段
    local numeric_fields=("issues_count" "warnings_count")
    for field in "${numeric_fields[@]}"; do
        local value
        value=$(echo "$summary_result" | jq -r ".$field")
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            echo "✅ $field 为有效数字"
        else
            echo "❌ $field 不是有效数字：$value"
            return 1
        fi
    done
    
    # 验证平台字段
    local platform
    platform=$(echo "$summary_result" | jq -r '.platform')
    if [[ -n "$platform" && "$platform" != "null" ]]; then
        echo "✅ 平台信息有效：$platform"
    else
        echo "❌ 平台信息无效：$platform"
        return 1
    fi
    
    # 验证版本字段格式
    local git_version
    git_version=$(echo "$summary_result" | jq -r '.git_version')
    if [[ -n "$git_version" && "$git_version" != "null" ]]; then
        echo "✅ Git版本信息有效：$git_version"
    else
        echo "❌ Git版本信息无效：$git_version"
        return 1
    fi
    
    # 验证与其他方法的一致性
    local issues_result
    issues_result=$(environment_get_issues)
    
    local summary_compatible summary_issues_count summary_warnings_count
    local issues_compatible issues_count warnings_count
    
    summary_compatible=$(echo "$summary_result" | jq -r '.compatible')
    summary_issues_count=$(echo "$summary_result" | jq -r '.issues_count')
    summary_warnings_count=$(echo "$summary_result" | jq -r '.warnings_count')
    
    issues_compatible=$(echo "$issues_result" | jq -r '.compatible')
    issues_count=$(echo "$issues_result" | jq -r '.issues | length')
    warnings_count=$(echo "$issues_result" | jq -r '.warnings | length')
    
    if [[ "$summary_compatible" == "$issues_compatible" ]]; then
        echo "✅ 兼容性状态与问题报告一致"
    else
        echo "❌ 兼容性状态与问题报告不一致"
        return 1
    fi
    
    if [[ "$summary_issues_count" == "$issues_count" ]]; then
        echo "✅ 问题数量与问题报告一致"
    else
        echo "❌ 问题数量与问题报告不一致：$summary_issues_count vs $issues_count"
        return 1
    fi
    
    if [[ "$summary_warnings_count" == "$warnings_count" ]]; then
        echo "✅ 警告数量与问题报告一致"
    else
        echo "❌ 警告数量与问题报告不一致：$summary_warnings_count vs $warnings_count"
        return 1
    fi
}

# 运行所有测试
run_test "environment_detect_complete" "test_environment_detect_complete"
run_test "environment_check_compatibility" "test_environment_check_compatibility"
run_test "environment_get_issues" "test_environment_get_issues"
run_test "environment_get_summary" "test_environment_get_summary"

print_test_summary