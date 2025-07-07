#!/bin/bash
# GPF Commands Layer - Status Command Simple Tests
# 简化的Commands层status.sh功能测试

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试辅助函数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${BLUE}🧪 运行测试: ${test_name}${NC}"
    
    if $test_function; then
        echo -e "${GREEN}✅ 通过: ${test_name}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ 失败: ${test_name}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo
}

# =============================================================================
# 基础语法和结构测试
# =============================================================================

test_status_command_file_exists() {
    [[ -f "$PROJECT_ROOT/lib/core/commands/status.sh" ]]
}

test_status_command_syntax() {
    bash -n "$PROJECT_ROOT/lib/core/commands/status.sh" 2>/dev/null
}

test_status_command_executable() {
    [[ -x "$PROJECT_ROOT/lib/core/commands/status.sh" ]]
}

test_status_command_functions_defined() {
    # 检查关键函数是否定义
    local functions_to_check=(
        "status_command_main"
        "status_command_process_parameters"
        "status_command_detect_and_prepare_environment"
        "status_command_collect_status_data"
        "status_command_format_and_display"
    )
    
    for func in "${functions_to_check[@]}"; do
        if ! grep -q "^${func}()" "$PROJECT_ROOT/lib/core/commands/status.sh"; then
            echo "❌ 函数 $func 未找到"
            return 1
        fi
    done
    return 0
}

# =============================================================================
# 命令行接口测试
# =============================================================================

test_help_option() {
    # 测试--help选项
    local output
    output=$(cd "$PROJECT_ROOT" && export GPF_TEST_MODE=true && bash lib/core/commands/status.sh --help 2>/dev/null)
    [[ "$output" == *"GPF Status Command"* ]]
}

test_invalid_option_handling() {
    # 测试无效选项处理
    if cd "$PROJECT_ROOT" && bash lib/core/commands/status.sh --invalid-option 2>/dev/null; then
        return 1  # 应该失败
    else
        return 0  # 正确失败
    fi
}

# =============================================================================
# 参数解析测试
# =============================================================================

test_format_option_parsing() {
    # 测试格式选项解析
    local output
    output=$(cd "$PROJECT_ROOT" && timeout 5 bash lib/core/commands/status.sh --format=json 2>/dev/null || echo "timeout")
    
    # 检查是否没有立即报错（可能会因为环境问题失败，但不应该是参数解析问题）
    [[ "$output" != *"未知选项"* && "$output" != *"过多的参数"* ]]
}

test_purpose_option_parsing() {
    # 测试目的选项解析
    local output
    output=$(cd "$PROJECT_ROOT" && timeout 5 bash lib/core/commands/status.sh --purpose=pr 2>/dev/null || echo "timeout")
    
    # 检查是否没有立即报错
    [[ "$output" != *"未知选项"* && "$output" != *"过多的参数"* ]]
}

# =============================================================================
# 代码质量测试
# =============================================================================

test_code_style_consistency() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查是否有合适的shebang
    local first_line
    first_line=$(head -1 "$file")
    [[ "$first_line" == "#!/bin/bash" ]]
}

test_error_handling_patterns() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查是否有错误处理
    if grep -q "set -euo pipefail" "$file" && grep -q "return 1" "$file"; then
        return 0
    else
        return 1
    fi
}

test_documentation_comments() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查是否有适当的注释
    local comment_count
    comment_count=$(grep -c "^#" "$file" || echo "0")
    [[ $comment_count -gt 10 ]]  # 至少应该有10行注释
}

# =============================================================================
# 架构合规性测试
# =============================================================================

test_layer_separation() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查是否只调用Modules层
    # 不应该直接调用Composite或Atomic层
    if grep -q "source.*composite" "$file" || grep -q "source.*atomic" "$file"; then
        echo "❌ 发现跨层调用：Commands层不应直接调用Composite或Atomic层"
        return 1
    fi
    
    # 应该调用Modules层
    if grep -q "source.*modules" "$file"; then
        return 0
    else
        echo "❌ 未找到Modules层调用"
        return 1
    fi
}

test_no_direct_git_calls() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # Commands层不应该有直接的git调用
    if grep -q "git " "$file" | grep -v "# " | grep -v "comment"; then
        echo "❌ 发现直接git调用：Commands层应通过Modules层调用"
        return 1
    fi
    return 0
}

# =============================================================================
# 输出格式测试
# =============================================================================

test_output_format_functions() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查是否有各种输出格式的函数
    local format_functions=(
        "status_command_format_compact"
        "status_command_format_human"
        "status_command_format_boolean"
    )
    
    for func in "${format_functions[@]}"; do
        if ! grep -q "$func" "$file"; then
            echo "❌ 输出格式函数 $func 未找到"
            return 1
        fi
    done
    return 0
}

# =============================================================================
# 模块化测试
# =============================================================================

test_function_organization() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查是否有适当的功能组织（通过分隔符检查）
    local section_count
    section_count=$(grep -c "# ====" "$file" || echo "0")
    [[ $section_count -gt 3 ]]  # 至少应该有4个主要部分
}

test_main_function_structure() {
    local file="$PROJECT_ROOT/lib/core/commands/status.sh"
    
    # 检查主函数是否有四个阶段
    local main_function_content
    main_function_content=$(sed -n '/^status_command_main()/,/^}/p' "$file")
    
    # 检查是否包含四个主要阶段的调用
    echo "$main_function_content" | grep -q "process_parameters" &&
    echo "$main_function_content" | grep -q "detect_and_prepare_environment" &&
    echo "$main_function_content" | grep -q "collect_status_data" &&
    echo "$main_function_content" | grep -q "format_and_display"
}

# =============================================================================
# 运行所有测试
# =============================================================================

main() {
    echo -e "${BLUE}🚀 开始运行GPF Commands层 Status命令简化测试套件...${NC}"
    echo "=============================================================="
    echo
    
    # 基础语法和结构测试
    echo -e "${YELLOW}📋 基础语法和结构测试${NC}"
    echo "========================"
    run_test "文件存在性检查" test_status_command_file_exists
    run_test "语法正确性检查" test_status_command_syntax
    run_test "文件可执行性检查" test_status_command_executable
    run_test "关键函数定义检查" test_status_command_functions_defined
    
    # 命令行接口测试
    echo -e "${YELLOW}🖥️ 命令行接口测试${NC}"
    echo "===================="
    run_test "帮助选项测试" test_help_option
    run_test "无效选项处理" test_invalid_option_handling
    
    # 参数解析测试
    echo -e "${YELLOW}⚙️ 参数解析测试${NC}"
    echo "=================="
    run_test "格式选项解析" test_format_option_parsing
    run_test "目的选项解析" test_purpose_option_parsing
    
    # 代码质量测试
    echo -e "${YELLOW}📊 代码质量测试${NC}"
    echo "=================="
    run_test "代码风格一致性" test_code_style_consistency
    run_test "错误处理模式" test_error_handling_patterns
    run_test "文档注释检查" test_documentation_comments
    
    # 架构合规性测试
    echo -e "${YELLOW}🏗️ 架构合规性测试${NC}"
    echo "==================="
    run_test "分层调用检查" test_layer_separation
    run_test "直接Git调用检查" test_no_direct_git_calls
    
    # 输出格式测试
    echo -e "${YELLOW}🎨 输出格式测试${NC}"
    echo "=================="
    run_test "输出格式函数检查" test_output_format_functions
    
    # 模块化测试
    echo -e "${YELLOW}🔧 模块化测试${NC}"
    echo "==============="
    run_test "功能组织检查" test_function_organization
    run_test "主函数结构检查" test_main_function_structure
    
    # 测试结果汇总
    echo
    echo -e "${BLUE}📊 测试结果汇总${NC}"
    echo "==============="
    echo "总测试数: $TOTAL_TESTS"
    echo -e "通过: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "失败: ${RED}$FAILED_TESTS${NC}"
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=$(( PASSED_TESTS * 100 / TOTAL_TESTS ))
        echo "成功率: ${success_rate}%"
    fi
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 所有Commands层 Status命令测试通过！${NC}"
        echo -e "${GREEN}✅ Commands层实现符合GPF架构标准${NC}"
        return 0
    else
        echo -e "${RED}❌ 有 $FAILED_TESTS 个测试失败${NC}"
        echo -e "${YELLOW}⚠️ 请修复失败的测试后再继续${NC}"
        return 1
    fi
}

# 如果直接执行此脚本，运行所有测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi