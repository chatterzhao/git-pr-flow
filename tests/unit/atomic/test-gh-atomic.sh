#!/bin/bash
# GPF Core - GitHub CLI Atomic Methods Tests
# 测试 gh-atomic.sh 中的所有原子方法

set -euo pipefail

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/../../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/core/atomic/gh-atomic.sh"

# 测试：gh_check_installation
test_gh_check_installation() {
    print_test_header "测试 gh_check_installation - GitHub CLI安装检查"
    
    # 模拟GitHub CLI已安装的情况
    if command -v gh >/dev/null 2>&1; then
        if gh_check_installation; then
            echo "✅ 检测到GitHub CLI已安装"
        else
            echo "❌ 未能检测到已安装的GitHub CLI"
            return 1
        fi
    else
        # GitHub CLI未安装时的测试
        if ! gh_check_installation; then
            echo "✅ 正确检测到GitHub CLI未安装"
        else
            echo "❌ 错误地认为GitHub CLI已安装"
            return 1
        fi
    fi
}

# 测试：gh_get_version
test_gh_get_version() {
    print_test_header "测试 gh_get_version - 获取GitHub CLI版本"
    
    local version
    version=$(gh_get_version)
    
    if command -v gh >/dev/null 2>&1; then
        if [[ -n "$version" ]]; then
            echo "✅ 成功获取版本：$version"
        else
            echo "❌ GitHub CLI已安装但无法获取版本"
            return 1
        fi
    else
        if [[ -z "$version" ]]; then
            echo "✅ GitHub CLI未安装时正确返回空版本"
        else
            echo "❌ GitHub CLI未安装但返回了版本：$version"
            return 1
        fi
    fi
}

# 测试：gh_check_auth
test_gh_check_auth() {
    print_test_header "测试 gh_check_auth - GitHub CLI认证检查"
    
    if ! command -v gh >/dev/null 2>&1; then
        if ! gh_check_auth; then
            echo "✅ GitHub CLI未安装时正确返回未认证状态"
        else
            echo "❌ GitHub CLI未安装但认为已认证"
            return 1
        fi
        return 0
    fi
    
    # GitHub CLI已安装的情况
    if gh_check_auth 2>/dev/null; then
        echo "✅ 检测到GitHub CLI已认证"
    else
        echo "✅ 检测到GitHub CLI未认证（这也是正常的）"
    fi
}

# 测试：gh_get_current_user
test_gh_get_current_user() {
    print_test_header "测试 gh_get_current_user - 获取当前用户"
    
    local user
    user=$(gh_get_current_user)
    
    if ! command -v gh >/dev/null 2>&1; then
        if [[ -z "$user" ]]; then
            echo "✅ GitHub CLI未安装时正确返回空用户"
        else
            echo "❌ GitHub CLI未安装但返回了用户：$user"
            return 1
        fi
        return 0
    fi
    
    # GitHub CLI已安装的情况
    if gh_check_auth 2>/dev/null; then
        if [[ -n "$user" ]]; then
            echo "✅ 成功获取认证用户：$user"
        else
            echo "⚠️ 已认证但无法获取用户信息"
        fi
    else
        if [[ -z "$user" ]]; then
            echo "✅ 未认证时正确返回空用户"
        else
            echo "❌ 未认证但返回了用户：$user"
            return 1
        fi
    fi
}

# 测试：gh_check_version_compatibility
test_gh_check_version_compatibility() {
    print_test_header "测试 gh_check_version_compatibility - 版本兼容性检查"
    
    if ! command -v gh >/dev/null 2>&1; then
        if ! gh_check_version_compatibility "2.0.0"; then
            echo "✅ GitHub CLI未安装时正确返回不兼容"
        else
            echo "❌ GitHub CLI未安装但认为版本兼容"
            return 1
        fi
        return 0
    fi
    
    # 测试与一个很低的版本比较（应该兼容）
    if gh_check_version_compatibility "1.0.0"; then
        echo "✅ 与低版本比较时正确返回兼容"
    else
        echo "❌ 与低版本比较时错误返回不兼容"
        return 1
    fi
    
    # 测试与一个很高的版本比较（可能不兼容）
    if ! gh_check_version_compatibility "999.0.0"; then
        echo "✅ 与高版本比较时正确返回不兼容"
    else
        echo "⚠️ 与高版本比较时返回兼容（当前版本可能很新）"
    fi
}

# 测试：gh_get_status
test_gh_get_status() {
    print_test_header "测试 gh_get_status - 获取GitHub CLI状态"
    
    local status
    status=$(gh_get_status)
    
    # 验证JSON格式
    if echo "$status" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("installed" "authenticated" "connected" "version" "user")
    for field in "${required_fields[@]}"; do
        if echo "$status" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证逻辑一致性
    local installed authenticated
    installed=$(echo "$status" | jq -r '.installed')
    authenticated=$(echo "$status" | jq -r '.authenticated')
    
    if [[ "$installed" == "false" && "$authenticated" == "true" ]]; then
        echo "❌ 逻辑错误：未安装但显示已认证"
        return 1
    else
        echo "✅ 状态逻辑一致"
    fi
}

# 测试：gh_check_command_available
test_gh_check_command_available() {
    print_test_header "测试 gh_check_command_available - 检查命令可用性"
    
    if ! command -v gh >/dev/null 2>&1; then
        if ! gh_check_command_available "pr"; then
            echo "✅ GitHub CLI未安装时正确返回命令不可用"
        else
            echo "❌ GitHub CLI未安装但认为命令可用"
            return 1
        fi
        return 0
    fi
    
    # 测试已知存在的命令
    if gh_check_command_available "pr"; then
        echo "✅ 正确检测到pr命令可用"
    else
        echo "❌ 未能检测到pr命令"
        return 1
    fi
    
    # 测试不存在的命令
    if ! gh_check_command_available "nonexistent-command-xyz"; then
        echo "✅ 正确检测到不存在的命令"
    else
        echo "❌ 错误地认为不存在的命令可用"
        return 1
    fi
}

# 测试：gh_list_available_commands
test_gh_list_available_commands() {
    print_test_header "测试 gh_list_available_commands - 列出可用命令"
    
    if ! command -v gh >/dev/null 2>&1; then
        if ! gh_list_available_commands >/dev/null 2>&1; then
            echo "✅ GitHub CLI未安装时正确处理"
        else
            echo "❌ GitHub CLI未安装但返回了命令列表"
            return 1
        fi
        return 0
    fi
    
    local commands
    commands=$(gh_list_available_commands)
    
    if [[ -n "$commands" ]]; then
        local command_count
        command_count=$(echo "$commands" | wc -l)
        echo "✅ 成功获取 $command_count 个可用命令"
        
        # 检查是否包含常见命令
        if echo "$commands" | grep -q "pr"; then
            echo "✅ 命令列表包含pr"
        else
            echo "❌ 命令列表不包含pr"
            return 1
        fi
    else
        echo "❌ 未能获取任何命令"
        return 1
    fi
}

# 运行所有测试
run_test "gh_check_installation" "test_gh_check_installation"
run_test "gh_get_version" "test_gh_get_version"
run_test "gh_check_auth" "test_gh_check_auth"
run_test "gh_get_current_user" "test_gh_get_current_user"
run_test "gh_check_version_compatibility" "test_gh_check_version_compatibility"
run_test "gh_get_status" "test_gh_get_status"
run_test "gh_check_command_available" "test_gh_check_command_available"
run_test "gh_list_available_commands" "test_gh_list_available_commands"

print_test_summary