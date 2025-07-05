#!/bin/bash
# GPF Status Module Tests
# 测试status-module.sh的所有功能

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 加载测试框架和被测试模块
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/modules/status-module.sh"

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试辅助函数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "🧪 运行测试: $test_name"
    
    if $test_function; then
        echo "✅ 通过: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ 失败: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo
}

# 模拟函数（用于测试隔离）
mock_git_operations() {
    # 模拟git命令
    git() {
        case "$*" in
            "-C"*"diff --quiet")
                return 0  # 模拟工作区干净
                ;;
            "-C"*"diff --cached --quiet")
                return 0  # 模拟暂存区干净
                ;;
            "-C"*"rev-parse origin/"*)
                return 0  # 模拟分支已推送
                ;;
            "-C"*"rev-list --count"*)
                echo "0"  # 模拟没有提交差异
                ;;
            "-C"*"merge-base"*)
                echo "abc123"  # 模拟merge base
                ;;
            *)
                command git "$@"  # 其他git命令正常执行
                ;;
        esac
    }
}

# 测试用例

# 测试1: 分支环境分析
test_analyze_branch_environment() {
    local result
    
    # 测试Epic分支
    result=$(status_module_analyze_branch_environment "epic-auth-e")
    [[ "$result" == "epic:$PROJECT_ROOT/.worktrees/epic-auth-e" ]] || return 1
    
    # 测试Feature分支
    result=$(status_module_analyze_branch_environment "epic-auth-e-login-ef")
    [[ "$result" == "feature:$PROJECT_ROOT/.worktrees/epic-auth-e-login-ef" ]] || return 1
    
    # 测试其他分支
    result=$(status_module_analyze_branch_environment "develop")
    [[ "$result" == "root:$PROJECT_ROOT" ]] || return 1
    
    return 0
}

# 测试2: 基础状态检查
test_get_base_status() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟git操作
    mock_git_operations
    
    local result
    result=$(status_module_get_base_status "test-branch" "$test_dir")
    
    # 验证返回的JSON格式
    local working_clean
    working_clean=$(echo "$result" | jq -r '.working_tree_clean')
    [[ "$working_clean" == "true" ]] || return 1
    
    local staging_clean
    staging_clean=$(echo "$result" | jq -r '.staging_area_clean')
    [[ "$staging_clean" == "true" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试3: 目标关系状态检查
test_get_target_relationship() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟git操作
    mock_git_operations
    
    local result
    result=$(status_module_get_target_relationship "test-branch" "develop" "$test_dir")
    
    # 验证返回的JSON格式
    local target_branch
    target_branch=$(echo "$result" | jq -r '.target_branch')
    [[ "$target_branch" == "develop" ]] || return 1
    
    local commits_ahead
    commits_ahead=$(echo "$result" | jq -r '.commits_ahead')
    [[ "$commits_ahead" == "0" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试4: GitHub状态检查
test_get_github_status() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    local result
    result=$(status_module_get_github_status "test-branch" "$test_dir")
    
    # 验证返回的JSON格式
    local gh_available
    gh_available=$(echo "$result" | jq -r '.gh_available')
    [[ "$gh_available" =~ ^(true|false)$ ]] || return 1
    
    local pr_exists
    pr_exists=$(echo "$result" | jq -r '.pr_exists')
    [[ "$pr_exists" =~ ^(true|false)$ ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试5: PR状态格式化
test_format_pr_status() {
    local base_status='{"working_tree_clean": true, "staging_area_clean": true, "branch_pushed": true}'
    local target_status='{"branch_merged": false, "needs_sync": false, "commits_ahead": 0, "commits_behind": 0}'
    local github_status='{"gh_available": true, "pr_exists": false, "pr_number": "", "pr_state": ""}'
    
    local result
    result=$(status_module_format_pr_status "test-branch" "develop" "$base_status" "$target_status" "$github_status")
    
    # 验证返回的JSON格式
    local purpose
    purpose=$(echo "$result" | jq -r '.purpose')
    [[ "$purpose" == "pr" ]] || return 1
    
    local pr_ready
    pr_ready=$(echo "$result" | jq -r '.pr_ready')
    [[ "$pr_ready" == "true" ]] || return 1
    
    return 0
}

# 测试6: 清理状态格式化
test_format_clean_status() {
    local base_status='{"working_tree_clean": true, "staging_area_clean": true, "branch_pushed": true}'
    local target_status='{"branch_merged": true}'
    local github_status='{"gh_available": true}'
    
    local result
    result=$(status_module_format_clean_status "test-branch" "$base_status" "$target_status" "$github_status")
    
    # 验证返回的JSON格式
    local purpose
    purpose=$(echo "$result" | jq -r '.purpose')
    [[ "$purpose" == "clean" ]] || return 1
    
    local safety_level
    safety_level=$(echo "$result" | jq -r '.safety_level')
    [[ "$safety_level" == "safe" ]] || return 1
    
    local safety_color
    safety_color=$(echo "$result" | jq -r '.safety_color')
    [[ "$safety_color" == "🟢" ]] || return 1
    
    return 0
}

# 测试7: 同步状态格式化
test_format_sync_status() {
    local base_status='{"working_tree_clean": true, "staging_area_clean": true}'
    local target_status='{"needs_sync": true, "commits_behind": 2}'
    
    local result
    result=$(status_module_format_sync_status "test-branch" "develop" "$base_status" "$target_status")
    
    # 验证返回的JSON格式
    local purpose
    purpose=$(echo "$result" | jq -r '.purpose')
    [[ "$purpose" == "sync" ]] || return 1
    
    local sync_ready
    sync_ready=$(echo "$result" | jq -r '.sync_ready')
    [[ "$sync_ready" == "true" ]] || return 1
    
    return 0
}

# 测试8: 通用状态格式化
test_format_general_status() {
    local base_status='{"working_tree_clean": true}'
    local target_status='{"branch_merged": false}'
    local github_status='{"gh_available": true}'
    
    local result
    result=$(status_module_format_general_status "test-branch" "$base_status" "$target_status" "$github_status")
    
    # 验证返回的JSON格式
    local purpose
    purpose=$(echo "$result" | jq -r '.purpose')
    [[ "$purpose" == "general" ]] || return 1
    
    local branch_name
    branch_name=$(echo "$result" | jq -r '.branch_name')
    [[ "$branch_name" == "test-branch" ]] || return 1
    
    return 0
}

# 测试9: 远程状态检查函数
test_remote_status_checks() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟git操作
    mock_git_operations
    
    # 测试工作区检查
    if check_working_tree_clean_remote "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 测试暂存区检查
    if check_staging_area_clean_remote "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 测试分支推送检查
    if check_branch_pushed_remote "test-branch" "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试10: 便捷检查函数
test_convenience_checks() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟git操作和status_module_get_complete_status
    status_module_get_complete_status() {
        local purpose="$3"
        case "$purpose" in
            "pr")
                echo '{"pr_ready": true}'
                ;;
            "clean")
                echo '{"safety_level": "safe"}'
                ;;
            "sync")
                echo '{"needs_sync": true}'
                ;;
        esac
    }
    
    # 测试PR准备检查
    if status_module_check_pr_ready "test-branch" "develop"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 测试清理安全检查
    if status_module_check_clean_safe "test-branch" "develop"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 测试同步需求检查
    if status_module_check_sync_needed "test-branch" "develop"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 运行所有测试
run_all_tests() {
    echo "🚀 开始运行Status Module测试套件..."
    echo "========================================"
    
    run_test "分支环境分析测试" test_analyze_branch_environment
    run_test "基础状态检查测试" test_get_base_status
    run_test "目标关系状态测试" test_get_target_relationship
    run_test "GitHub状态检查测试" test_get_github_status
    run_test "PR状态格式化测试" test_format_pr_status
    run_test "清理状态格式化测试" test_format_clean_status
    run_test "同步状态格式化测试" test_format_sync_status
    run_test "通用状态格式化测试" test_format_general_status
    run_test "远程状态检查测试" test_remote_status_checks
    run_test "便捷检查函数测试" test_convenience_checks
    
    echo "========================================"
    echo "📊 测试结果统计:"
    echo "   总测试数: $TOTAL_TESTS"
    echo "   通过: $PASSED_TESTS"
    echo "   失败: $FAILED_TESTS"
    echo "   成功率: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "🎉 所有测试通过！"
        return 0
    else
        echo "💥 有测试失败！"
        return 1
    fi
}

# 执行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi