#!/bin/bash
# GPF Core - Roadmap Composite Methods Tests
# 测试 roadmap-composite.sh 中的所有组合方法

set -euo pipefail

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/../../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/core/composite/roadmap-composite.sh"

# 测试目录设置
TEST_DIR="/tmp/test_roadmap_composite_$$"
TEST_REPO="$TEST_DIR/test_repo"

# 设置测试Git仓库
setup_test_repo() {
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    
    # 初始化Git仓库
    git init >/dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # 创建初始提交
    echo "初始文件" > README.md
    git add README.md
    git commit -m "初始提交" >/dev/null 2>&1
    
    # 创建develop分支
    git checkout -b develop >/dev/null 2>&1
    echo "develop分支" >> README.md
    git add README.md
    git commit -m "创建develop分支" >/dev/null 2>&1
}

# 清理函数
cleanup() {
    cd /
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 测试：roadmap_initialize_epic
test_roadmap_initialize_epic() {
    print_test_header "测试 roadmap_initialize_epic - Epic Roadmap初始化"
    
    setup_test_repo
    
    local result
    result=$(roadmap_initialize_epic "test-epic" "develop" "$TEST_REPO")
    
    # 验证JSON格式
    if echo "$result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("success" "epic_name" "roadmap_file" "base_branch" "created_at")
    for field in "${required_fields[@]}"; do
        if echo "$result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证成功状态
    local success
    success=$(echo "$result" | jq -r '.success')
    if [[ "$success" == "true" ]]; then
        echo "✅ 初始化成功"
    else
        echo "❌ 初始化失败"
        return 1
    fi
    
    # 验证Epic名称
    local epic_name
    epic_name=$(echo "$result" | jq -r '.epic_name')
    if [[ "$epic_name" == "test-epic" ]]; then
        echo "✅ Epic名称正确"
    else
        echo "❌ Epic名称错误：$epic_name"
        return 1
    fi
    
    # 验证roadmap文件是否创建
    local roadmap_file
    roadmap_file=$(echo "$result" | jq -r '.roadmap_file')
    if [[ -f "$roadmap_file" ]]; then
        echo "✅ Roadmap文件创建成功"
    else
        echo "❌ Roadmap文件未创建"
        return 1
    fi
    
    # 验证文件内容
    if grep -q "# Epic: \[test-epic\]" "$roadmap_file"; then
        echo "✅ Roadmap文件内容正确"
    else
        echo "❌ Roadmap文件内容不正确"
        return 1
    fi
    
    # 测试重复初始化（应该返回警告）
    local result2
    result2=$(roadmap_initialize_epic "test-epic" "develop" "$TEST_REPO" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 2 ]]; then
        echo "✅ 重复初始化正确返回警告状态"
    else
        echo "❌ 重复初始化处理不正确"
        return 1
    fi
}

# 测试：roadmap_validate_epic_commit
test_roadmap_validate_epic_commit() {
    print_test_header "测试 roadmap_validate_epic_commit - Epic分支提交验证"
    
    setup_test_repo
    
    # 首先创建一个Epic roadmap
    roadmap_initialize_epic "validation-test" "develop" "$TEST_REPO" >/dev/null 2>&1
    
    # 创建Epic分支
    git checkout -b epic-validation-test-e develop >/dev/null 2>&1
    
    # 添加roadmap文件到分支
    mkdir -p docs/epic_roadmap
    echo "# Epic: [validation-test]" > docs/epic_roadmap/epic-validation-test-roadmap.md
    git add docs/epic_roadmap/epic-validation-test-roadmap.md
    git commit -m "添加roadmap" >/dev/null 2>&1
    
    # 测试验证
    local result
    result=$(roadmap_validate_epic_commit "epic-validation-test-e" "$TEST_REPO")
    
    # 验证JSON格式
    if echo "$result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("success" "epic_branch" "epic_name" "safe_to_merge" "validation_report" "validated_at")
    for field in "${required_fields[@]}"; do
        if echo "$result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证成功状态
    local success
    success=$(echo "$result" | jq -r '.success')
    if [[ "$success" == "true" ]]; then
        echo "✅ 验证成功"
    else
        echo "❌ 验证失败"
        return 1
    fi
    
    # 验证Epic分支名
    local epic_branch
    epic_branch=$(echo "$result" | jq -r '.epic_branch')
    if [[ "$epic_branch" == "epic-validation-test-e" ]]; then
        echo "✅ Epic分支名正确"
    else
        echo "❌ Epic分支名错误：$epic_branch"
        return 1
    fi
    
    # 验证安全合并状态
    local safe_to_merge
    safe_to_merge=$(echo "$result" | jq -r '.safe_to_merge')
    if [[ "$safe_to_merge" == "true" ]]; then
        echo "✅ 可以安全合并"
    else
        echo "❌ 无法安全合并"
        return 1
    fi
    
    # 测试包含代码文件的情况（应该验证失败）
    mkdir -p src
    echo "代码文件" > src/app.js
    git add src/app.js
    git commit -m "添加代码文件" >/dev/null 2>&1
    
    if ! roadmap_validate_epic_commit "epic-validation-test-e" "$TEST_REPO" >/dev/null 2>&1; then
        echo "✅ 包含代码文件时正确验证失败"
    else
        echo "❌ 包含代码文件时错误验证通过"
        return 1
    fi
}

# 测试：roadmap_update_feature_status
test_roadmap_update_feature_status() {
    print_test_header "测试 roadmap_update_feature_status - 更新Feature状态"
    
    setup_test_repo
    
    # 创建包含Feature的roadmap
    roadmap_initialize_epic "status-test" "develop" "$TEST_REPO" >/dev/null 2>&1
    
    local roadmap_file="$TEST_REPO/docs/epic_roadmap/epic-status-test-roadmap.md"
    
    # 手动添加一个Feature到roadmap
    cat >> "$roadmap_file" << 'EOF'

## 子Feature规划
1. **status-test-login** - 登录功能 ⏳ **待实现**
EOF
    
    # 测试更新Feature状态
    if roadmap_update_feature_status "status-test" "login" "已完成" "$TEST_REPO"; then
        echo "✅ Feature状态更新成功"
    else
        echo "❌ Feature状态更新失败"
        return 1
    fi
    
    # 验证文件内容是否更新
    if grep -q "status-test-login" "$roadmap_file" && grep -q "✅" "$roadmap_file" && grep -q "已完成" "$roadmap_file"; then
        echo "✅ Roadmap文件内容已正确更新"
    else
        echo "❌ Roadmap文件内容未正确更新"
        echo "文件内容："
        cat "$roadmap_file"
        return 1
    fi
    
    # 测试无效状态
    if ! roadmap_update_feature_status "status-test" "login" "无效状态" "$TEST_REPO" 2>/dev/null; then
        echo "✅ 无效状态正确被拒绝"
    else
        echo "❌ 无效状态错误被接受"
        return 1
    fi
    
    # 测试不存在的Feature
    if ! roadmap_update_feature_status "status-test" "nonexistent" "已完成" "$TEST_REPO" 2>/dev/null; then
        echo "✅ 不存在的Feature正确被拒绝"
    else
        echo "❌ 不存在的Feature错误被接受"
        return 1
    fi
}

# 测试：roadmap_get_status_summary
test_roadmap_get_status_summary() {
    print_test_header "测试 roadmap_get_status_summary - 获取状态总结"
    
    setup_test_repo
    
    # 测试不存在的roadmap
    local result
    result=$(roadmap_get_status_summary "nonexistent" "$TEST_REPO" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 1 ]]; then
        echo "✅ 不存在的roadmap正确返回错误"
    else
        echo "❌ 不存在的roadmap处理不正确"
        return 1
    fi
    
    # 验证不存在roadmap的返回格式
    if echo "$result" | jq -e '.exists == false' >/dev/null 2>&1; then
        echo "✅ 不存在roadmap的JSON格式正确"
    else
        echo "❌ 不存在roadmap的JSON格式错误"
        return 1
    fi
    
    # 创建roadmap进行测试
    roadmap_initialize_epic "summary-test" "develop" "$TEST_REPO" >/dev/null 2>&1
    
    # 测试存在的roadmap
    result=$(roadmap_get_status_summary "summary-test" "$TEST_REPO")
    
    # 验证JSON格式
    if echo "$result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("exists" "epic_name" "roadmap_file" "status" "info" "summary_generated_at")
    for field in "${required_fields[@]}"; do
        if echo "$result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证存在状态
    local exists
    exists=$(echo "$result" | jq -r '.exists')
    if [[ "$exists" == "true" ]]; then
        echo "✅ 正确识别roadmap存在"
    else
        echo "❌ 未正确识别roadmap存在"
        return 1
    fi
    
    # 验证Epic名称
    local epic_name
    epic_name=$(echo "$result" | jq -r '.epic_name')
    if [[ "$epic_name" == "summary-test" ]]; then
        echo "✅ Epic名称正确"
    else
        echo "❌ Epic名称错误：$epic_name"
        return 1
    fi
    
    # 验证时间戳格式
    local timestamp
    timestamp=$(echo "$result" | jq -r '.summary_generated_at')
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        echo "✅ 时间戳格式正确"
    else
        echo "❌ 时间戳格式错误：$timestamp"
        return 1
    fi
}

# 运行所有测试
run_test "roadmap_initialize_epic" "test_roadmap_initialize_epic"
run_test "roadmap_validate_epic_commit" "test_roadmap_validate_epic_commit"
run_test "roadmap_update_feature_status" "test_roadmap_update_feature_status"
run_test "roadmap_get_status_summary" "test_roadmap_get_status_summary"

print_test_summary