#!/bin/bash

# 测试智能分支解析功能
# 用于验证paths_module_smart_branch_resolve方法的前缀后缀处理

source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core/modules/paths-module.sh"

# 测试套件：智能分支解析
test_suite_smart_branch_resolve() {
    echo "🧪 测试套件：智能分支解析"
    
    # 设置测试环境
    setup_test_environment
    
    # 测试用例：基本前缀后缀处理
    test_basic_prefix_suffix_handling
    
    # 测试用例：存在性检查优先级
    test_existence_priority_check
    
    # 测试用例：Epic vs Feature 智能匹配
    test_epic_vs_feature_matching
    
    # 测试用例：上下文感知匹配
    test_context_aware_matching
    
    # 清理测试环境
    cleanup_test_environment
}

# 设置测试环境
setup_test_environment() {
    echo "📝 设置测试环境..."
    
    # 创建测试用的worktree目录
    mkdir -p "$PWD/.worktrees"
    
    # 模拟存在的worktree
    mkdir -p "$PWD/.worktrees/epic-aa-e"
    mkdir -p "$PWD/.worktrees/epic-aa-e-login-ef"
    mkdir -p "$PWD/.worktrees/epic-bb-e"
    mkdir -p "$PWD/.worktrees/epic-test-e"
    
    echo "✅ 测试环境设置完成"
}

# 清理测试环境
cleanup_test_environment() {
    echo "🧹 清理测试环境..."
    # 移除测试用的worktree目录（如果需要的话）
    echo "✅ 测试环境清理完成"
}

# 测试基本前缀后缀处理
test_basic_prefix_suffix_handling() {
    echo "🔍 测试基本前缀后缀处理..."
    
    # 测试用例矩阵
    local test_cases=(
        # 输入:期望输出:描述
        "aa:epic-aa-e:简单名称转Epic分支"
        "aa-e:epic-aa-e:带-e后缀转Epic分支"
        "epic-aa:epic-aa-e:带epic-前缀转Epic分支"
        "epic-aa-e:epic-aa-e:完整Epic分支名保持不变"
        "login:epic-aa-e-login-ef:简单Feature名称(需要Epic上下文)"
        "aa-login:epic-aa-e-login-ef:复合Feature名称"
        "epic-aa-e-login-ef:epic-aa-e-login-ef:完整Feature分支名保持不变"
    )
    
    for test_case in "${test_cases[@]}"; do
        IFS=':' read -r input expected description <<< "$test_case"
        
        echo "  📋 测试: $description"
        echo "    输入: $input"
        echo "    期望: $expected"
        
        # 调用智能解析方法
        local result
        result=$(paths_module_smart_branch_resolve "$input" 2>/dev/null)
        local exit_code=$?
        
        if [[ $exit_code -eq 0 && "$result" == "$expected" ]]; then
            echo "    结果: ✅ PASS - $result"
        else
            echo "    结果: ❌ FAIL - 得到: $result (期望: $expected)"
            test_failed "基本前缀后缀处理失败: $input -> $result (期望: $expected)"
        fi
        echo
    done
}

# 测试存在性检查优先级
test_existence_priority_check() {
    echo "🔍 测试存在性检查优先级..."
    
    # 测试场景：输入 "aa" 时，既有 epic-aa-e 又有 epic-aa-e-login-ef
    echo "  📋 测试: 多个匹配时的优先级选择"
    echo "    场景: 输入 'aa' 时存在 epic-aa-e 和 epic-aa-e-login-ef"
    
    local result
    result=$(paths_module_smart_branch_resolve "aa" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        if [[ "$result" == "epic-aa-e" ]]; then
            echo "    结果: ✅ PASS - 优先选择Epic分支: $result"
        elif [[ "$result" == "epic-aa-e-login-ef" ]]; then
            echo "    结果: ⚠️  WARN - 选择了Feature分支: $result (可接受但非最优)"
        else
            echo "    结果: ❌ FAIL - 意外结果: $result"
            test_failed "存在性检查优先级失败"
        fi
    else
        echo "    结果: ❌ FAIL - 方法执行失败"
        test_failed "存在性检查方法执行失败"
    fi
    echo
}

# 测试Epic vs Feature智能匹配
test_epic_vs_feature_matching() {
    echo "🔍 测试Epic vs Feature智能匹配..."
    
    # 测试在不同环境下的行为
    local test_scenarios=(
        # 环境:输入:期望行为:描述
        "root:aa:epic-aa-e:根环境下简单名称优先匹配Epic"
        "root:login:epic-aa-e-login-ef:根环境下Feature名称需要完整匹配"
        "epic:login:epic-{current}-e-login-ef:Epic环境下Feature名称使用当前Epic上下文"
    )
    
    for scenario in "${test_scenarios[@]}"; do
        IFS=':' read -r environment input expected description <<< "$scenario"
        
        echo "  📋 测试: $description"
        echo "    环境: $environment"
        echo "    输入: $input"
        echo "    期望: $expected"
        
        # 这里需要根据实际实现调整测试逻辑
        # 暂时跳过，等实现完成后补充
        echo "    结果: ⏭️  SKIP - 待实现"
        echo
    done
}

# 测试上下文感知匹配
test_context_aware_matching() {
    echo "🔍 测试上下文感知匹配..."
    
    echo "  📋 测试: 当前环境影响解析结果"
    echo "    场景: 在Epic环境下解析Feature名称"
    
    # 这里需要模拟不同的环境上下文
    # 暂时跳过，等实现完成后补充
    echo "    结果: ⏭️  SKIP - 待实现"
    echo
}

# 运行测试套件
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_suite_smart_branch_resolve
fi