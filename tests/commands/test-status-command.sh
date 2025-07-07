#!/bin/bash
# GPF Commands Layer - Status Command Tests
# 测试Commands层status.sh的完整功能

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 避免变量冲突，设置测试环境
export GPF_TEST_MODE="true"

# 加载测试框架（如果存在）
[[ -f "$PROJECT_ROOT/tests/test-framework.sh" ]] && source "$PROJECT_ROOT/tests/test-framework.sh" || true

# 检查Commands层文件是否存在
if [[ ! -f "$PROJECT_ROOT/lib/commands/status.sh" ]]; then
    echo "❌ 错误：Commands层status.sh文件不存在"
    exit 1
fi

# 加载Commands层文件用于测试
source "$PROJECT_ROOT/lib/commands/status.sh"

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试辅助函数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "🧪 运行Commands层测试: $test_name"
    
    if $test_function; then
        echo "✅ 通过: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ 失败: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo
}

# Mock functions for testing isolation
setup_test_environment() {
    # 创建临时测试目录结构
    TEST_WORKTREE_BASE="$PROJECT_ROOT/.worktrees"
    TEST_EPIC_DIR="$TEST_WORKTREE_BASE/epic-test-e"
    TEST_FEATURE_DIR="$TEST_WORKTREE_BASE/epic-test-e-login-ef"
    
    mkdir -p "$TEST_EPIC_DIR" "$TEST_FEATURE_DIR" 2>/dev/null || true
}

cleanup_test_environment() {
    # 清理测试环境
    rm -rf "$PROJECT_ROOT/.worktrees/epic-test-e" "$PROJECT_ROOT/.worktrees/epic-test-e-login-ef" 2>/dev/null || true
}

# Mock Modules层函数用于测试
mock_modules_functions() {
    # Mock environment_module_get_current_context
    environment_module_get_current_context() {
        cat <<EOF
{
    "type": "root",
    "current_path": "$PROJECT_ROOT",
    "project_root": "$PROJECT_ROOT",
    "epic_name": "",
    "feature_name": ""
}
EOF
    }
    
    # Mock paths_module_smart_branch_resolve
    paths_module_smart_branch_resolve() {
        local input="$1"
        case "$input" in
            "auth") echo "epic-auth-e" ;;
            "login") echo "epic-auth-e-login-ef" ;;
            *) echo "$input" ;;
        esac
    }
    
    # Mock paths_module_validate_user_input
    paths_module_validate_user_input() {
        local input="$1"
        [[ -n "$input" && ! "$input" =~ [^a-zA-Z0-9_-] ]]
    }
    
    # Mock status_module_get_complete_status
    status_module_get_complete_status() {
        local branch="$1"
        local target="$2"
        local purpose="$3"
        
        cat <<EOF
{
    "purpose": "$purpose",
    "branch_name": "$branch",
    "target_branch": "$target",
    "pr_ready": true,
    "start_ready": true,
    "sync_ready": false,
    "safety_level": "safe",
    "blocking_issues": [],
    "warnings": [],
    "base_status": {
        "working_tree_clean": true,
        "staging_area_clean": true,
        "branch_pushed": true,
        "has_merge_conflicts": false,
        "branch_exists": true
    },
    "target_status": {
        "branch_merged": false,
        "needs_sync": false,
        "commits_ahead": 2,
        "commits_behind": 0,
        "target_branch": "$target"
    },
    "github_status": {
        "gh_available": true,
        "pr_exists": false,
        "pr_number": "",
        "pr_state": ""
    }
}
EOF
    }
    
    # Mock worktree_module_quick_status
    worktree_module_quick_status() {
        cat <<EOF
{
    "branch_name": "epic-test-e",
    "working_clean": true,
    "staging_clean": true,
    "branch_pushed": true
}
EOF
    }
}

# =============================================================================
# 第一阶段测试：参数处理
# =============================================================================

test_parameter_processing_valid_formats() {
    local result
    result=$(status_command_process_parameters "" "json" "status" "{}")
    
    # 检查JSON格式是否正确
    if echo "$result" | jq . >/dev/null 2>&1; then
        local format=$(echo "$result" | jq -r '.output_format')
        [[ "$format" == "json" ]]
    else
        return 1
    fi
}

test_parameter_processing_invalid_format() {
    if status_command_process_parameters "" "invalid" "status" "{}" 2>/dev/null; then
        return 1  # 应该失败
    else
        return 0  # 正确失败
    fi
}

test_parameter_processing_target_resolution() {
    # Mock paths functions
    mock_modules_functions
    
    local result
    result=$(status_command_process_parameters "auth" "human" "status" "{}")
    
    if echo "$result" | jq . >/dev/null 2>&1; then
        local target_branch=$(echo "$result" | jq -r '.target_branch')
        [[ "$target_branch" == "epic-auth-e" ]]
    else
        return 1
    fi
}

test_parameter_processing_invalid_purpose() {
    if status_command_process_parameters "" "human" "invalid" "{}" 2>/dev/null; then
        return 1  # 应该失败
    else
        return 0  # 正确失败
    fi
}

# =============================================================================
# 第二阶段测试：环境检测
# =============================================================================

test_environment_detection_root() {
    mock_modules_functions
    
    local processed_params='{"target_input": "", "processed_target": "", "target_branch": "", "output_format": "human", "status_purpose": "status", "options": {}}'
    local result
    result=$(status_command_detect_and_prepare_environment "$processed_params")
    
    if echo "$result" | jq . >/dev/null 2>&1; then
        local current_type=$(echo "$result" | jq -r '.current_context.type')
        [[ "$current_type" == "root" ]]
    else
        return 1
    fi
}

test_environment_detection_with_target() {
    mock_modules_functions
    
    local processed_params='{"target_input": "auth", "processed_target": "epic-auth-e", "target_branch": "epic-auth-e", "output_format": "human", "status_purpose": "status", "options": {}}'
    local result
    result=$(status_command_detect_and_prepare_environment "$processed_params")
    
    if echo "$result" | jq . >/dev/null 2>&1; then
        local requires_switching=$(echo "$result" | jq -r '.requires_switching')
        [[ "$requires_switching" == "true" ]]
    else
        return 1
    fi
}

# =============================================================================
# 第三阶段测试：状态收集
# =============================================================================

test_status_collection_basic() {
    mock_modules_functions
    
    local environment_context='{"current_context": {"type": "root", "current_path": "'$PROJECT_ROOT'", "project_root": "'$PROJECT_ROOT'"}, "target_context": {"type": "root"}, "requires_switching": false, "status_purpose": "status"}'
    local processed_params='{"target_input": "", "processed_target": "", "target_branch": "", "output_format": "human", "status_purpose": "status", "options": {}}'
    
    local result
    result=$(status_command_collect_status_data "$environment_context" "$processed_params")
    
    if echo "$result" | jq . >/dev/null 2>&1; then
        local status_purpose=$(echo "$result" | jq -r '.status_purpose')
        [[ "$status_purpose" == "status" ]]
    else
        return 1
    fi
}

test_status_collection_with_target() {
    mock_modules_functions
    
    local environment_context='{"current_context": {"type": "root"}, "target_context": {"type": "epic", "target_branch": "epic-auth-e"}, "requires_switching": true, "status_purpose": "pr"}'
    local processed_params='{"target_input": "auth", "processed_target": "epic-auth-e", "target_branch": "epic-auth-e", "output_format": "human", "status_purpose": "pr", "options": {}}'
    
    local result
    result=$(status_command_collect_status_data "$environment_context" "$processed_params")
    
    if echo "$result" | jq . >/dev/null 2>&1; then
        local branch_to_check=$(echo "$result" | jq -r '.branch_to_check')
        [[ "$branch_to_check" == "epic-auth-e" ]]
    else
        return 1
    fi
}

# =============================================================================
# 第四阶段测试：输出格式化
# =============================================================================

test_format_json_output() {
    mock_modules_functions
    
    local status_data='{"branch_to_check": "epic-test-e", "target_branch_for_status": "develop", "status_purpose": "status", "complete_status": {"purpose": "status", "branch_name": "epic-test-e"}, "environment_info": {"environment_type": "root"}}'
    local processed_params='{"output_format": "json", "status_purpose": "status"}'
    
    local result
    result=$(status_command_format_and_display "$status_data" "$processed_params" 2>/dev/null)
    
    # 检查输出是否为有效JSON
    echo "$result" | jq . >/dev/null 2>&1
}

test_format_compact_output() {
    mock_modules_functions
    
    local status_data='{"branch_to_check": "epic-test-e", "status_purpose": "status", "complete_status": {"base_status": {"working_tree_clean": true, "staging_area_clean": true, "has_merge_conflicts": false}}}'
    local processed_params='{"output_format": "compact"}'
    
    local result
    result=$(status_command_format_and_display "$status_data" "$processed_params" 2>/dev/null)
    
    # 检查紧凑输出是否包含分支名
    [[ "$result" == *"epic-test-e"* ]]
}

test_format_human_output() {
    mock_modules_functions
    
    local status_data='{"branch_to_check": "epic-test-e", "target_branch_for_status": "develop", "status_purpose": "status", "complete_status": {"purpose": "status", "base_status": {"working_tree_clean": true, "staging_area_clean": true, "branch_pushed": true, "has_merge_conflicts": false}}, "environment_info": {"environment_type": "root"}}'
    local processed_params='{"output_format": "human", "status_purpose": "status"}'
    
    local result
    result=$(status_command_format_and_display "$status_data" "$processed_params" 2>/dev/null)
    
    # 检查人类可读输出是否包含状态报告标题
    [[ "$result" == *"Status Report"* ]]
}

# =============================================================================
# 集成测试
# =============================================================================

test_main_function_integration() {
    mock_modules_functions
    setup_test_environment
    
    # 测试基本status命令
    local result
    result=$(status_command_main "" "json" "status" "{}" 2>/dev/null)
    
    local success=0
    if echo "$result" | jq . >/dev/null 2>&1; then
        success=1
    fi
    
    cleanup_test_environment
    [[ $success -eq 1 ]]
}

test_main_function_with_target() {
    mock_modules_functions
    setup_test_environment
    
    # 测试带目标的status命令
    local result
    result=$(status_command_main "auth" "compact" "pr" "{}" 2>/dev/null)
    
    local success=0
    if [[ -n "$result" ]]; then
        success=1
    fi
    
    cleanup_test_environment
    [[ $success -eq 1 ]]
}

test_error_handling() {
    mock_modules_functions
    
    # 测试无效参数的错误处理
    if status_command_main "" "invalid_format" "status" "{}" 2>/dev/null; then
        return 1  # 应该失败
    else
        return 0  # 正确失败
    fi
}

# =============================================================================
# 辅助功能测试
# =============================================================================

test_boolean_formatting() {
    local result_true
    local result_false
    result_true=$(status_command_format_boolean "true")
    result_false=$(status_command_format_boolean "false")
    
    [[ "$result_true" == "✅ Yes" && "$result_false" == "❌ No" ]]
}

test_help_display() {
    local result
    result=$(status_command_show_help)
    
    # 检查帮助信息是否包含关键字
    [[ "$result" == *"GPF Status Command"* && "$result" == *"用法"* ]]
}

# =============================================================================
# 运行所有测试
# =============================================================================

main() {
    echo "🚀 开始运行GPF Commands层 Status命令测试套件..."
    echo "=================================================="
    echo
    
    # 第一阶段：参数处理测试
    echo "📋 第一阶段：参数处理测试"
    echo "========================"
    run_test "参数处理-有效格式" test_parameter_processing_valid_formats
    run_test "参数处理-无效格式" test_parameter_processing_invalid_format
    run_test "参数处理-目标解析" test_parameter_processing_target_resolution
    run_test "参数处理-无效目的" test_parameter_processing_invalid_purpose
    
    # 第二阶段：环境检测测试
    echo "🌍 第二阶段：环境检测测试"
    echo "========================"
    run_test "环境检测-根环境" test_environment_detection_root
    run_test "环境检测-带目标" test_environment_detection_with_target
    
    # 第三阶段：状态收集测试
    echo "📊 第三阶段：状态收集测试"
    echo "========================"
    run_test "状态收集-基础功能" test_status_collection_basic
    run_test "状态收集-带目标" test_status_collection_with_target
    
    # 第四阶段：输出格式化测试
    echo "🎨 第四阶段：输出格式化测试"
    echo "=========================="
    run_test "格式化-JSON输出" test_format_json_output
    run_test "格式化-紧凑输出" test_format_compact_output
    run_test "格式化-人类可读输出" test_format_human_output
    
    # 集成测试
    echo "🔧 集成测试"
    echo "==========="
    run_test "主函数-集成测试" test_main_function_integration
    run_test "主函数-带目标测试" test_main_function_with_target
    run_test "错误处理测试" test_error_handling
    
    # 辅助功能测试
    echo "🛠️ 辅助功能测试"
    echo "==============="
    run_test "布尔值格式化" test_boolean_formatting
    run_test "帮助显示" test_help_display
    
    # 测试结果汇总
    echo "📊 测试结果汇总"
    echo "==============="
    echo "总测试数: $TOTAL_TESTS"
    echo "通过: $PASSED_TESTS"
    echo "失败: $FAILED_TESTS"
    echo "成功率: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "🎉 所有Commands层 Status命令测试通过！"
        return 0
    else
        echo "❌ 有 $FAILED_TESTS 个测试失败"
        return 1
    fi
}

# 如果直接执行此脚本，运行所有测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi