#!/bin/bash
# NewGPF Test Framework
# 统一的测试运行框架

set -euo pipefail

# 测试框架配置
readonly TEST_FRAMEWORK_VERSION="1.0.0"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-$(pwd)/test-results}"
TEST_VERBOSE="${TEST_VERBOSE:-0}"
TEST_PARALLEL="${TEST_PARALLEL:-1}"

# 测试统计
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 测试结果数组
TEST_FAILURES=()
TEST_SUCCESSES=()

# 颜色输出
readonly T_RED='\033[0;31m'
readonly T_GREEN='\033[0;32m'
readonly T_YELLOW='\033[1;33m'
readonly T_BLUE='\033[0;34m'
readonly T_RESET='\033[0m'

# 测试输出函数
test_log() {
    local level="$1"
    shift
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${T_BLUE}[INFO $timestamp]${T_RESET} $*"
            ;;
        "PASS")
            echo -e "${T_GREEN}[PASS $timestamp]${T_RESET} $*"
            ;;
        "FAIL")
            echo -e "${T_RED}[FAIL $timestamp]${T_RESET} $*"
            ;;
        "WARN")
            echo -e "${T_YELLOW}[WARN $timestamp]${T_RESET} $*"
            ;;
        "DEBUG")
            if [[ "$TEST_VERBOSE" == "1" ]]; then
                echo -e "${T_BLUE}[DEBUG $timestamp]${T_RESET} $*"
            fi
            ;;
    esac
}

# 断言函数
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "期望值: '$expected'"
        echo "实际值: '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$not_expected" != "$actual" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "不期望值: '$not_expected'"
        echo "实际值: '$actual'"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-}"
    
    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "期望: true，实际: $condition"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-}"
    
    if [[ "$condition" == "false" ]] || [[ "$condition" != "0" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "期望: false，实际: $condition"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "在 '$haystack' 中未找到 '$needle'"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-}"
    
    if [[ -f "$file_path" ]]; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "文件不存在: $file_path"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-}"
    
    if eval "$command" >/dev/null 2>&1; then
        return 0
    else
        local exit_code=$?
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "命令执行失败: $command (退出码: $exit_code)"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local message="${2:-}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        return 0
    else
        if [[ -n "$message" ]]; then
            echo "断言失败: $message"
        fi
        echo "命令应该失败但成功了: $command"
        return 1
    fi
}

# Mock工具
mock_command() {
    local command_name="$1"
    local mock_output="$2"
    local mock_exit_code="${3:-0}"
    
    # 创建mock函数
    eval "$command_name() { 
        echo '$mock_output'
        return $mock_exit_code
    }"
    
    test_log "DEBUG" "已Mock命令: $command_name -> 输出:'$mock_output', 退出码:$mock_exit_code"
}

mock_file() {
    local file_path="$1"
    local content="$2"
    
    mkdir -p "$(dirname "$file_path")"
    echo "$content" > "$file_path"
    
    test_log "DEBUG" "已Mock文件: $file_path"
}

# 测试用例执行
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    test_log "INFO" "开始测试: $test_name"
    
    # 创建临时目录
    local test_temp_dir
    test_temp_dir=$(mktemp -d -t "newgpf-test-XXXXXX")
    export TEST_TEMP_DIR="$test_temp_dir"
    
    local start_time
    start_time=$(date +%s%N)
    
    # 执行测试
    local test_result=0
    local test_output
    if test_output=$($test_function 2>&1); then
        local end_time
        end_time=$(date +%s%N)
        local duration_ms=$(( (end_time - start_time) / 1000000 ))
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TEST_SUCCESSES+=("$test_name")
        test_log "PASS" "$test_name (${duration_ms}ms)"
        
        if [[ "$TEST_VERBOSE" == "1" && -n "$test_output" ]]; then
            echo "$test_output"
        fi
    else
        test_result=$?
        local end_time
        end_time=$(date +%s%N)
        local duration_ms=$(( (end_time - start_time) / 1000000 ))
        
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_FAILURES+=("$test_name: $test_output")
        test_log "FAIL" "$test_name (${duration_ms}ms)"
        echo "$test_output"
    fi
    
    # 清理临时目录
    rm -rf "$test_temp_dir"
    unset TEST_TEMP_DIR
    
    return $test_result
}

# 测试套件运行
run_test_suite() {
    local suite_name="$1"
    shift
    local test_functions=("$@")
    
    test_log "INFO" "开始测试套件: $suite_name"
    
    local suite_start_time
    suite_start_time=$(date +%s)
    
    for test_function in "${test_functions[@]}"; do
        # 提取测试名称（移除test_前缀）
        local test_name="${test_function#test_}"
        run_test "$test_name" "$test_function"
    done
    
    local suite_end_time
    suite_end_time=$(date +%s)
    local suite_duration=$((suite_end_time - suite_start_time))
    
    test_log "INFO" "测试套件 '$suite_name' 完成，耗时 ${suite_duration}s"
}

# 生成测试报告
generate_test_report() {
    local report_file="${TEST_RESULTS_DIR}/test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    mkdir -p "$TEST_RESULTS_DIR"
    
    cat > "$report_file" << EOF
NewGPF 测试报告
================
生成时间: $(date)
测试框架版本: $TEST_FRAMEWORK_VERSION

测试统计:
- 总数: $TESTS_TOTAL
- 通过: $TESTS_PASSED
- 失败: $TESTS_FAILED
- 跳过: $TESTS_SKIPPED
- 成功率: $(( TESTS_TOTAL > 0 ? (TESTS_PASSED * 100) / TESTS_TOTAL : 0 ))%

EOF

    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
        echo "失败的测试:" >> "$report_file"
        printf '%s\n' "${TEST_FAILURES[@]}" >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    if [[ ${#TEST_SUCCESSES[@]} -gt 0 ]]; then
        echo "成功的测试:" >> "$report_file"
        printf '%s\n' "${TEST_SUCCESSES[@]}" >> "$report_file"
    fi
    
    test_log "INFO" "测试报告已生成: $report_file"
}

# 显示测试总结
show_test_summary() {
    echo ""
    echo "========================"
    echo "测试执行总结"
    echo "========================"
    echo "总数: $TESTS_TOTAL"
    echo -e "通过: ${T_GREEN}$TESTS_PASSED${T_RESET}"
    echo -e "失败: ${T_RED}$TESTS_FAILED${T_RESET}"
    echo "跳过: $TESTS_SKIPPED"
    
    if [[ $TESTS_TOTAL -gt 0 ]]; then
        local success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
        echo "成功率: $success_rate%"
    fi
    
    echo "========================"
    
    # 如果有失败，返回非零退出码
    [[ $TESTS_FAILED -eq 0 ]]
}

# 性能基准测试
benchmark_function() {
    local function_name="$1"
    local iterations="${2:-100}"
    
    test_log "INFO" "开始基准测试: $function_name (${iterations}次迭代)"
    
    local total_time=0
    local min_time=999999999
    local max_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time
        start_time=$(date +%s%N)
        
        "$function_name" >/dev/null 2>&1 || true
        
        local end_time
        end_time=$(date +%s%N)
        local duration=$((end_time - start_time))
        
        total_time=$((total_time + duration))
        
        if [[ $duration -lt $min_time ]]; then
            min_time=$duration
        fi
        
        if [[ $duration -gt $max_time ]]; then
            max_time=$duration
        fi
    done
    
    local avg_time_ns=$((total_time / iterations))
    local avg_time_ms=$((avg_time_ns / 1000000))
    local min_time_ms=$((min_time / 1000000))
    local max_time_ms=$((max_time / 1000000))
    
    echo "基准测试结果 - $function_name:"
    echo "  平均时间: ${avg_time_ms}ms"
    echo "  最小时间: ${min_time_ms}ms"
    echo "  最大时间: ${max_time_ms}ms"
    echo "  总迭代数: $iterations"
}

# 初始化测试框架
init_test_framework() {
    test_log "INFO" "初始化测试框架 v$TEST_FRAMEWORK_VERSION"
    
    # 重置统计
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
    
    TEST_FAILURES=()
    TEST_SUCCESSES=()
    
    # 创建结果目录
    mkdir -p "$TEST_RESULTS_DIR"
}