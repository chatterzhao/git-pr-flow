#!/bin/bash
# GPF GitHub Module Tests
# 测试github-module.sh的所有功能

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 加载测试框架和被测试模块
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/modules/github-module.sh"

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
mock_github_operations() {
    # 模拟GitHub CLI命令
    gh() {
        case "$1" in
            "pr")
                case "$2" in
                    "create")
                        echo "https://github.com/test/repo/pull/123"
                        return 0
                        ;;
                    "merge")
                        echo "✓ Merged pull request #123"
                        return 0
                        ;;
                    "close")
                        echo "✓ Closed pull request #123"
                        return 0
                        ;;
                esac
                ;;
        esac
        return 0
    }
    
    # 模拟git命令
    git() {
        case "$*" in
            "remote get-url origin")
                echo "https://github.com/test/repo.git"
                ;;
            "rev-parse"*)
                return 0
                ;;
            "push"*)
                return 0
                ;;
            "log --oneline"*)
                echo "abc123 test commit"
                ;;
            "rev-list --count"*)
                echo "1"
                ;;
            *)
                command git "$@"
                ;;
        esac
    }
    
    # 模拟GitHub检查函数
    gh_check_installation() { return 0; }
    gh_check_auth() { return 0; }
    gh_check_connectivity() { return 0; }
    github_pr_query_by_branch() { return 1; }  # 默认没有PR
}

# 测试用例

# 测试1: 环境验证
test_validate_environment() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    (cd "$test_dir" && git remote add origin https://github.com/test/repo.git)
    
    # 模拟GitHub操作
    mock_github_operations
    
    # 测试环境验证
    if github_module_validate_environment "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试2: 仓库配置验证
test_validate_repository() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    (cd "$test_dir" && git remote add origin https://github.com/test/repo.git)
    
    # 模拟git操作
    mock_github_operations
    
    # 测试仓库验证
    if github_module_validate_repository "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试3: 仓库信息获取
test_get_repository_info() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    (cd "$test_dir" && git remote add origin https://github.com/test/repo.git)
    
    # 模拟git操作
    mock_github_operations
    
    local result
    result=$(github_module_get_repository_info "$test_dir")
    
    # 验证返回的JSON格式
    local repo_owner
    repo_owner=$(echo "$result" | jq -r '.repo_owner')
    [[ "$repo_owner" == "test" ]] || return 1
    
    local repo_name
    repo_name=$(echo "$result" | jq -r '.repo_name')
    [[ "$repo_name" == "repo" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试4: PR存在检查
test_check_pr_exists() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 模拟GitHub操作
    mock_github_operations
    
    # 测试PR不存在的情况
    if ! github_module_check_pr_exists "test-branch" "$test_dir"; then
        # 测试通过（PR不存在）
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试5: 分支推送确保
test_ensure_branch_pushed() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟GitHub操作
    mock_github_operations
    
    # 测试分支推送
    if github_module_ensure_branch_pushed "test-branch" "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试6: PR标题生成
test_generate_pr_title() {
    # 测试Feature分支
    local result
    result=$(github_module_generate_pr_title "epic-auth-e-login-ef" "epic-auth-e")
    [[ "$result" == "feat(auth): login" ]] || return 1
    
    # 测试Epic分支
    result=$(github_module_generate_pr_title "epic-auth-e" "develop")
    [[ "$result" == "epic: auth" ]] || return 1
    
    # 测试其他分支
    result=$(github_module_generate_pr_title "feature-branch" "develop")
    [[ "$result" == "feature-branch → develop" ]] || return 1
    
    return 0
}

# 测试7: PR描述生成
test_generate_pr_body() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟git操作
    mock_github_operations
    
    local result
    result=$(github_module_generate_pr_body "test-branch" "develop" "$test_dir")
    
    # 验证包含基本结构
    [[ "$result" =~ "## 变更概述" ]] || return 1
    [[ "$result" =~ "源分支:" ]] || return 1
    [[ "$result" =~ "目标分支:" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试8: PR信息生成
test_generate_pr_info() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    
    # 模拟git操作
    mock_github_operations
    
    local result
    result=$(github_module_generate_pr_info "test-branch" "develop" "$test_dir" "")
    
    # 验证返回的JSON格式
    local source_branch
    source_branch=$(echo "$result" | jq -r '.source_branch')
    [[ "$source_branch" == "test-branch" ]] || return 1
    
    local target_branch
    target_branch=$(echo "$result" | jq -r '.target_branch')
    [[ "$target_branch" == "develop" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试9: PR创建执行
test_execute_pr_creation() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    (cd "$test_dir" && git remote add origin https://github.com/test/repo.git)
    
    # 模拟GitHub操作
    mock_github_operations
    
    local pr_info='{"source_branch": "test-branch", "target_branch": "develop", "title": "Test PR", "body": "Test description"}'
    
    local result
    result=$(github_module_execute_pr_creation "$pr_info" "$test_dir")
    
    # 验证返回的JSON格式
    local success
    success=$(echo "$result" | jq -r '.success')
    [[ "$success" == "true" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试10: PR状态查询
test_query_pr_status() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 模拟GitHub操作
    mock_github_operations
    
    local result
    result=$(github_module_query_pr_status "test-branch" "$test_dir")
    
    # 验证返回的JSON格式
    local available
    available=$(echo "$result" | jq -r '.available')
    [[ "$available" =~ ^(true|false)$ ]] || return 1
    
    local pr_exists
    pr_exists=$(echo "$result" | jq -r '.pr_exists')
    [[ "$pr_exists" =~ ^(true|false)$ ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试11: PR管理操作
test_manage_pr() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    (cd "$test_dir" && git remote add origin https://github.com/test/repo.git)
    
    # 模拟GitHub操作和PR查询
    mock_github_operations
    github_pr_query_by_branch() {
        echo '{"number": 123, "state": "open"}'
        return 0
    }
    
    # 测试合并操作
    if github_module_merge_pr "123" "$test_dir" ""; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 测试关闭操作
    if github_module_close_pr "123" "$test_dir"; then
        # 测试通过
        :
    else
        return 1
    fi
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试12: 批量PR状态查询
test_batch_query_pr_status() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktrees"
    mkdir -p "$test_dir/epic-test-e"
    
    # 初始化git仓库
    (cd "$test_dir/epic-test-e" && git init >/dev/null 2>&1)
    
    # 模拟GitHub操作
    mock_github_operations
    
    local result
    result=$(github_module_batch_query_pr_status "epic-test-e" "$test_dir")
    
    # 验证返回的JSON格式
    local available
    available=$(echo "$result" | jq -r '.available')
    [[ "$available" =~ ^(true|false)$ ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 测试13: 完整PR创建流程
test_create_pr_workflow() {
    # 创建临时测试目录
    local test_dir="$PROJECT_ROOT/.test_worktree"
    mkdir -p "$test_dir"
    
    # 初始化git仓库
    (cd "$test_dir" && git init >/dev/null 2>&1)
    (cd "$test_dir" && git remote add origin https://github.com/test/repo.git)
    
    # 模拟GitHub操作
    mock_github_operations
    
    # 重新定义github_module_validate_environment为成功
    github_module_validate_environment() { return 0; }
    github_module_check_pr_exists() { return 1; }  # PR不存在
    github_module_ensure_branch_pushed() { return 0; }
    
    local result
    result=$(github_module_create_pr "test-branch" "develop" "$test_dir" "")
    
    # 验证返回的JSON格式
    local success
    success=$(echo "$result" | jq -r '.success')
    [[ "$success" == "true" ]] || return 1
    
    # 清理测试目录
    rm -rf "$test_dir"
    
    return 0
}

# 运行所有测试
run_all_tests() {
    echo "🚀 开始运行GitHub Module测试套件..."
    echo "========================================"
    
    run_test "环境验证测试" test_validate_environment
    run_test "仓库配置验证测试" test_validate_repository
    run_test "仓库信息获取测试" test_get_repository_info
    run_test "PR存在检查测试" test_check_pr_exists
    run_test "分支推送确保测试" test_ensure_branch_pushed
    run_test "PR标题生成测试" test_generate_pr_title
    run_test "PR描述生成测试" test_generate_pr_body
    run_test "PR信息生成测试" test_generate_pr_info
    run_test "PR创建执行测试" test_execute_pr_creation
    run_test "PR状态查询测试" test_query_pr_status
    run_test "PR管理操作测试" test_manage_pr
    run_test "批量PR状态查询测试" test_batch_query_pr_status
    run_test "完整PR创建流程测试" test_create_pr_workflow
    
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