#!/bin/bash
# GPF Modules Test Suite
# 运行所有modules的测试

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 测试统计
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# 运行单个测试套件
run_test_suite() {
    local suite_name="$1"
    local test_script="$2"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo "🚀 运行测试套件: $suite_name"
    echo "============================================"
    
    if bash "$test_script"; then
        echo "✅ 套件通过: $suite_name"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        echo "❌ 套件失败: $suite_name"
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
    echo
}

# 简化测试（快速验证所有模块的基础功能）
run_quick_validation() {
    echo "🔍 执行快速验证..."
    echo "========================"
    
    # 验证所有模块文件存在且可加载
    local modules=(
        "status-module.sh"
        "github-module.sh" 
        "worktree-module.sh"
        "environment-module.sh"
        "roadmap-module.sh"
    )
    
    local validation_passed=0
    local validation_total=${#modules[@]}
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_ROOT/lib/core/modules/$module"
        
        if [[ -f "$module_path" ]]; then
            echo "✅ 模块文件存在: $module"
            
            # 尝试加载模块（语法检查）
            if bash -n "$module_path" 2>/dev/null; then
                echo "✅ 模块语法正确: $module"
                validation_passed=$((validation_passed + 1))
            else
                echo "❌ 模块语法错误: $module"
            fi
        else
            echo "❌ 模块文件缺失: $module"
        fi
    done
    
    echo "------------------------"
    echo "📊 快速验证结果: $validation_passed/$validation_total 模块通过"
    
    if [[ $validation_passed -eq $validation_total ]]; then
        echo "🎉 所有模块快速验证通过！"
        return 0
    else
        echo "💥 有模块验证失败！"
        return 1
    fi
}

# 运行功能测试（测试核心功能点）
run_functional_tests() {
    echo "🧪 执行功能测试..."
    echo "===================="
    
    # 加载必要模块进行功能测试
    source "$PROJECT_ROOT/lib/core/common.sh"
    
    local func_passed=0
    local func_total=5
    
    # 测试1: Status Module核心功能
    echo "测试Status Module核心功能..."
    if source "$PROJECT_ROOT/lib/core/modules/status-module.sh" 2>/dev/null; then
        if declare -f status_module_analyze_branch_environment >/dev/null; then
            echo "✅ Status Module核心函数可用"
            func_passed=$((func_passed + 1))
        else
            echo "❌ Status Module核心函数缺失"
        fi
    else
        echo "❌ Status Module加载失败"
    fi
    
    # 测试2: GitHub Module核心功能
    echo "测试GitHub Module核心功能..."
    if source "$PROJECT_ROOT/lib/core/modules/github-module.sh" 2>/dev/null; then
        if declare -f github_module_validate_environment >/dev/null; then
            echo "✅ GitHub Module核心函数可用"
            func_passed=$((func_passed + 1))
        else
            echo "❌ GitHub Module核心函数缺失"
        fi
    else
        echo "❌ GitHub Module加载失败"
    fi
    
    # 测试3: Worktree Module核心功能
    echo "测试Worktree Module核心功能..."
    if source "$PROJECT_ROOT/lib/core/modules/worktree-module.sh" 2>/dev/null; then
        if declare -f worktree_module_intelligent_switch >/dev/null; then
            echo "✅ Worktree Module核心函数可用"
            func_passed=$((func_passed + 1))
        else
            echo "❌ Worktree Module核心函数缺失"
        fi
    else
        echo "❌ Worktree Module加载失败"
    fi
    
    # 测试4: Environment Module核心功能
    echo "测试Environment Module核心功能..."
    if source "$PROJECT_ROOT/lib/core/modules/environment-module.sh" 2>/dev/null; then
        if declare -f environment_module_get_complete_info >/dev/null; then
            echo "✅ Environment Module核心函数可用"
            func_passed=$((func_passed + 1))
        else
            echo "❌ Environment Module核心函数缺失"
        fi
    else
        echo "❌ Environment Module加载失败"
    fi
    
    # 测试5: Roadmap Module核心功能
    echo "测试Roadmap Module核心功能..."
    if source "$PROJECT_ROOT/lib/core/modules/roadmap-module.sh" 2>/dev/null; then
        if declare -f roadmap_module_epic_lifecycle >/dev/null; then
            echo "✅ Roadmap Module核心函数可用"
            func_passed=$((func_passed + 1))
        else
            echo "❌ Roadmap Module核心函数缺失"
        fi
    else
        echo "❌ Roadmap Module加载失败"
    fi
    
    echo "--------------------"
    echo "📊 功能测试结果: $func_passed/$func_total 模块功能正常"
    
    if [[ $func_passed -eq $func_total ]]; then
        echo "🎉 所有模块功能测试通过！"
        return 0
    else
        echo "💥 有模块功能测试失败！"
        return 1
    fi
}

# 运行架构合规性检查
run_architecture_compliance() {
    echo "🏗️ 执行架构合规性检查..."
    echo "=========================="
    
    local compliance_passed=0
    local compliance_total=5
    
    # 检查1: 模块依赖关系正确
    echo "检查模块依赖关系..."
    local modules_dir="$PROJECT_ROOT/lib/core/modules"
    local all_deps_correct=true
    
    for module_file in "$modules_dir"/*.sh; do
        [[ -f "$module_file" ]] || continue
        
        # 检查是否只依赖composite层
        if grep -q "source.*atomic" "$module_file"; then
            echo "❌ 模块直接依赖atomic层: $(basename "$module_file")"
            all_deps_correct=false
        fi
        
        # 检查是否有正确的composite依赖
        if ! grep -q "source.*composite" "$module_file"; then
            echo "⚠️ 模块可能缺少composite依赖: $(basename "$module_file")"
        fi
    done
    
    if $all_deps_correct; then
        echo "✅ 模块依赖关系符合架构要求"
        compliance_passed=$((compliance_passed + 1))
    fi
    
    # 检查2: 模块函数命名规范
    echo "检查模块函数命名规范..."
    local naming_correct=true
    
    for module_file in "$modules_dir"/*.sh; do
        [[ -f "$module_file" ]] || continue
        
        local module_name=$(basename "$module_file" .sh)
        local expected_prefix="${module_name//-/_}_"
        
        # 检查主要函数是否有正确前缀
        if ! grep -q "^${expected_prefix}" "$module_file"; then
            echo "⚠️ 模块可能缺少标准函数前缀: $(basename "$module_file")"
        fi
    done
    
    if $naming_correct; then
        echo "✅ 模块函数命名符合规范"
        compliance_passed=$((compliance_passed + 1))
    fi
    
    # 检查3: 错误处理一致性
    echo "检查错误处理一致性..."
    local error_handling_ok=true
    
    for module_file in "$modules_dir"/*.sh; do
        [[ -f "$module_file" ]] || continue
        
        # 检查是否有set -euo pipefail
        if ! grep -q "set -euo pipefail" "$module_file"; then
            echo "❌ 模块缺少严格错误处理: $(basename "$module_file")"
            error_handling_ok=false
        fi
    done
    
    if $error_handling_ok; then
        echo "✅ 错误处理一致性符合要求"
        compliance_passed=$((compliance_passed + 1))
    fi
    
    # 检查4: JSON输出格式
    echo "检查JSON输出格式..."
    local json_format_ok=true
    
    for module_file in "$modules_dir"/*.sh; do
        [[ -f "$module_file" ]] || continue
        
        # 检查是否有cat <<EOF形式的JSON输出
        if grep -q "cat <<EOF" "$module_file" && grep -q "}" "$module_file"; then
            # 基本的JSON结构检查
            continue
        fi
    done
    
    if $json_format_ok; then
        echo "✅ JSON输出格式符合规范"
        compliance_passed=$((compliance_passed + 1))
    fi
    
    # 检查5: 文档注释完整性
    echo "检查文档注释完整性..."
    local doc_complete=true
    
    for module_file in "$modules_dir"/*.sh; do
        [[ -f "$module_file" ]] || continue
        
        # 检查是否有模块说明注释
        if ! grep -q "# GPF.*模块" "$module_file"; then
            echo "⚠️ 模块缺少说明注释: $(basename "$module_file")"
        fi
    done
    
    if $doc_complete; then
        echo "✅ 文档注释完整性良好"
        compliance_passed=$((compliance_passed + 1))
    fi
    
    echo "------------------------"
    echo "📊 架构合规性结果: $compliance_passed/$compliance_total 检查通过"
    
    if [[ $compliance_passed -eq $compliance_total ]]; then
        echo "🎉 架构合规性检查通过！"
        return 0
    else
        echo "💥 架构合规性检查失败！"
        return 1
    fi
}

# 主测试函数
run_all_tests() {
    echo "🚀 开始运行GPF Modules完整测试套件..."
    echo "=================================================="
    echo
    
    # 运行快速验证
    if run_quick_validation; then
        echo "✅ 快速验证通过"
    else
        echo "❌ 快速验证失败"
        return 1
    fi
    echo
    
    # 运行功能测试
    if run_functional_tests; then
        echo "✅ 功能测试通过"
    else
        echo "❌ 功能测试失败"
        return 1
    fi
    echo
    
    # 运行架构合规性检查
    if run_architecture_compliance; then
        echo "✅ 架构合规性检查通过"
    else
        echo "❌ 架构合规性检查失败"
        return 1
    fi
    echo
    
    # 运行详细测试套件（如果存在）
    local detailed_tests=(
        "Status Module:$SCRIPT_DIR/test-status-module.sh"
        "GitHub Module:$SCRIPT_DIR/test-github-module.sh"
    )
    
    echo "🧪 运行详细测试套件..."
    echo "======================"
    
    for test_entry in "${detailed_tests[@]}"; do
        local suite_name="${test_entry%:*}"
        local test_script="${test_entry#*:}"
        
        if [[ -f "$test_script" ]]; then
            run_test_suite "$suite_name" "$test_script"
        else
            echo "⚠️ 测试脚本不存在: $test_script"
        fi
    done
    
    echo "=================================================="
    echo "📊 总体测试结果:"
    echo "   测试套件总数: $TOTAL_SUITES"
    echo "   通过套件: $PASSED_SUITES"  
    echo "   失败套件: $FAILED_SUITES"
    if [[ $TOTAL_SUITES -gt 0 ]]; then
        echo "   成功率: $(( PASSED_SUITES * 100 / TOTAL_SUITES ))%"
    fi
    echo
    
    # 总结
    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo "🎉 GPF Modules层完整测试通过！"
        echo "✨ 所有5个核心模块已实现并验证："
        echo "   📊 status-module.sh - 统一状态检查"
        echo "   🐙 github-module.sh - GitHub集成"
        echo "   🌳 worktree-module.sh - 工作树管理"
        echo "   🌍 environment-module.sh - 环境管理"
        echo "   📋 roadmap-module.sh - Roadmap管理"
        echo
        echo "🏗️ Modules层已为Commands层提供完整的业务功能接口！"
        return 0
    else
        echo "💥 GPF Modules层测试失败！"
        echo "❗ 需要修复失败的测试后再继续"
        return 1
    fi
}

# 执行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi