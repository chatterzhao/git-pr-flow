#!/bin/bash
# GPF Core - Epic Validation Atomic Methods Tests
# 测试 epic-validation.sh 中的所有原子方法

set -euo pipefail

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/../../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/core/atomic/epic-validation.sh"

# 测试目录设置
TEST_DIR="/tmp/test_epic_validation_$$"
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
    
    # 创建docs目录结构
    mkdir -p docs/epic_roadmap
}

# 清理函数
cleanup() {
    cd /
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 测试：epic_validate_branch_naming
test_epic_validate_branch_naming() {
    print_test_header "测试 epic_validate_branch_naming - Epic分支命名验证"
    
    # 测试有效的Epic分支名
    local valid_names=("epic-auth-e" "epic-user-management-e" "epic-api-v2-e")
    for name in "${valid_names[@]}"; do
        if epic_validate_branch_naming "$name"; then
            echo "✅ 有效分支名通过验证: $name"
        else
            echo "❌ 有效分支名未通过验证: $name"
            return 1
        fi
    done
    
    # 测试无效的Epic分支名
    local invalid_names=("epic-auth" "auth-e" "epic-auth-ef" "epic-Auth-e" "epic--e")
    for name in "${invalid_names[@]}"; do
        if ! epic_validate_branch_naming "$name"; then
            echo "✅ 无效分支名正确被拒绝: $name"
        else
            echo "❌ 无效分支名错误通过验证: $name"
            return 1
        fi
    done
}

# 测试：epic_extract_name_from_branch
test_epic_extract_name_from_branch() {
    print_test_header "测试 epic_extract_name_from_branch - 从分支名提取Epic名称"
    
    # 测试有效分支名的提取
    local test_cases=(
        "epic-auth-e:auth"
        "epic-user-management-e:user-management"
        "epic-api-v2-e:api-v2"
    )
    
    for case in "${test_cases[@]}"; do
        local branch_name="${case%:*}"
        local expected_name="${case#*:}"
        local extracted_name
        extracted_name=$(epic_extract_name_from_branch "$branch_name")
        
        if [[ "$extracted_name" == "$expected_name" ]]; then
            echo "✅ 正确提取Epic名称: $branch_name -> $extracted_name"
        else
            echo "❌ Epic名称提取错误: $branch_name -> $extracted_name (期望: $expected_name)"
            return 1
        fi
    done
    
    # 测试无效分支名的提取
    local epic_name
    epic_name=$(epic_extract_name_from_branch "invalid-branch")
    if [[ -z "$epic_name" ]]; then
        echo "✅ 无效分支名正确返回空名称"
    else
        echo "❌ 无效分支名返回了名称: $epic_name"
        return 1
    fi
}

# 测试：epic_check_roadmap_only (需要Git仓库)
test_epic_check_roadmap_only() {
    print_test_header "测试 epic_check_roadmap_only - 检查Epic分支只包含roadmap"
    
    setup_test_repo
    
    # 创建测试Epic分支
    git checkout -b epic-test-e develop >/dev/null 2>&1
    
    # 测试空分支（没有修改）
    if epic_check_roadmap_only "epic-test-e" "$TEST_REPO"; then
        echo "✅ 空Epic分支正确通过检查"
    else
        echo "❌ 空Epic分支未通过检查"
        return 1
    fi
    
    # 添加roadmap文件
    echo "# Epic: [test]" > docs/epic_roadmap/epic-test-roadmap.md
    git add docs/epic_roadmap/epic-test-roadmap.md
    git commit -m "添加roadmap" >/dev/null 2>&1
    
    # 测试只包含roadmap文件的分支
    if epic_check_roadmap_only "epic-test-e" "$TEST_REPO"; then
        echo "✅ 只包含roadmap的Epic分支正确通过检查"
    else
        echo "❌ 只包含roadmap的Epic分支未通过检查"
        return 1
    fi
    
    # 添加非roadmap文件
    mkdir -p src
    echo "代码文件" > src/code.js
    git add src/code.js
    git commit -m "添加代码文件" >/dev/null 2>&1
    
    # 测试包含非roadmap文件的分支
    if ! epic_check_roadmap_only "epic-test-e" "$TEST_REPO"; then
        echo "✅ 包含非roadmap文件的Epic分支正确被拒绝"
    else
        echo "❌ 包含非roadmap文件的Epic分支错误通过检查"
        return 1
    fi
    
    # 测试不存在的分支
    if ! epic_check_roadmap_only "nonexistent-branch" "$TEST_REPO"; then
        echo "✅ 不存在的分支正确被拒绝"
    else
        echo "❌ 不存在的分支错误通过检查"
        return 1
    fi
}

# 测试：epic_validate_commit_files
test_epic_validate_commit_files() {
    print_test_header "测试 epic_validate_commit_files - 验证Epic提交文件类型"
    
    setup_test_repo
    
    # 创建测试Epic分支
    git checkout -b epic-validation-test-e develop >/dev/null 2>&1
    
    # 添加允许的文件类型
    mkdir -p docs/epic_roadmap
    echo "# Epic roadmap" > docs/epic_roadmap/epic-validation-test-roadmap.md
    echo "# Documentation" > docs/additional-doc.md
    echo "# Project README" > README.md
    echo "*.log" > .gitignore
    
    git add .
    git commit -m "添加允许的文件" >/dev/null 2>&1
    
    # 测试允许的文件类型
    if epic_validate_commit_files "epic-validation-test-e" "$TEST_REPO"; then
        echo "✅ 允许的文件类型正确通过验证"
    else
        echo "❌ 允许的文件类型未通过验证"
        return 1
    fi
    
    # 添加不允许的文件类型
    mkdir -p src
    echo "console.log('code');" > src/app.js
    git add src/app.js
    git commit -m "添加代码文件" >/dev/null 2>&1
    
    # 测试不允许的文件类型
    if ! epic_validate_commit_files "epic-validation-test-e" "$TEST_REPO"; then
        echo "✅ 不允许的文件类型正确被拒绝"
    else
        echo "❌ 不允许的文件类型错误通过验证"
        return 1
    fi
}

# 测试：epic_get_modified_files
test_epic_get_modified_files() {
    print_test_header "测试 epic_get_modified_files - 获取Epic修改文件列表"
    
    setup_test_repo
    
    # 测试不存在的分支
    local result
    result=$(epic_get_modified_files "nonexistent-branch" "$TEST_REPO")
    
    if echo "$result" | jq -e '.valid == false' >/dev/null 2>&1; then
        echo "✅ 不存在分支正确返回invalid"
    else
        echo "❌ 不存在分支返回结果不正确"
        return 1
    fi
    
    # 创建测试分支并添加文件
    git checkout -b epic-files-test-e develop >/dev/null 2>&1
    
    mkdir -p docs/epic_roadmap src
    echo "# Roadmap" > docs/epic_roadmap/epic-files-test-roadmap.md
    echo "# Docs" > docs/other-doc.md
    echo "code" > src/app.js
    
    git add .
    git commit -m "添加测试文件" >/dev/null 2>&1
    
    # 测试有修改文件的分支
    result=$(epic_get_modified_files "epic-files-test-e" "$TEST_REPO")
    
    # 验证JSON格式
    if echo "$result" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("valid" "files" "roadmap_files" "other_files" "total")
    for field in "${required_fields[@]}"; do
        if echo "$result" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证文件分类
    local roadmap_count other_count
    roadmap_count=$(echo "$result" | jq '.roadmap_files | length')
    other_count=$(echo "$result" | jq '.other_files | length')
    
    if [[ "$roadmap_count" == "1" ]]; then
        echo "✅ 正确识别roadmap文件数量"
    else
        echo "❌ roadmap文件数量不正确：$roadmap_count"
        return 1
    fi
    
    if [[ "$other_count" == "2" ]]; then
        echo "✅ 正确识别其他文件数量"
    else
        echo "❌ 其他文件数量不正确：$other_count"
        return 1
    fi
}

# 测试：epic_validate_roadmap_completeness
test_epic_validate_roadmap_completeness() {
    print_test_header "测试 epic_validate_roadmap_completeness - 验证roadmap完整性"
    
    setup_test_repo
    
    # 创建测试分支
    git checkout -b epic-roadmap-complete-e develop >/dev/null 2>&1
    
    # 测试缺少roadmap文件的情况
    if ! epic_validate_roadmap_completeness "roadmap-complete" "epic-roadmap-complete-e" "$TEST_REPO"; then
        echo "✅ 缺少roadmap文件正确被拒绝"
    else
        echo "❌ 缺少roadmap文件错误通过验证"
        return 1
    fi
    
    # 添加正确的roadmap文件
    mkdir -p docs/epic_roadmap
    echo "# Epic: [roadmap-complete]" > docs/epic_roadmap/epic-roadmap-complete-roadmap.md
    git add docs/epic_roadmap/epic-roadmap-complete-roadmap.md
    git commit -m "添加roadmap文件" >/dev/null 2>&1
    
    # 测试包含正确roadmap文件的情况
    if epic_validate_roadmap_completeness "roadmap-complete" "epic-roadmap-complete-e" "$TEST_REPO"; then
        echo "✅ 包含正确roadmap文件通过验证"
    else
        echo "❌ 包含正确roadmap文件未通过验证"
        return 1
    fi
    
    # 测试错误的Epic名称
    if ! epic_validate_roadmap_completeness "wrong-name" "epic-roadmap-complete-e" "$TEST_REPO"; then
        echo "✅ 错误Epic名称正确被拒绝"
    else
        echo "❌ 错误Epic名称错误通过验证"
        return 1
    fi
}

# 测试：epic_get_commit_info
test_epic_get_commit_info() {
    print_test_header "测试 epic_get_commit_info - 获取Epic提交信息"
    
    setup_test_repo
    
    # 测试不存在的分支
    local commit_info
    commit_info=$(epic_get_commit_info "nonexistent-branch" "$TEST_REPO")
    
    if echo "$commit_info" | jq -e '.valid == false' >/dev/null 2>&1; then
        echo "✅ 不存在分支正确返回invalid"
    else
        echo "❌ 不存在分支返回结果不正确"
        return 1
    fi
    
    # 创建有提交的测试分支
    git checkout -b epic-commits-e develop >/dev/null 2>&1
    
    # 添加几个提交
    echo "commit 1" > file1.txt
    git add file1.txt
    git commit -m "第一个提交" >/dev/null 2>&1
    
    echo "commit 2" > file2.txt
    git add file2.txt
    git commit -m "第二个提交" >/dev/null 2>&1
    
    # 测试有提交的分支
    commit_info=$(epic_get_commit_info "epic-commits-e" "$TEST_REPO")
    
    # 验证JSON格式
    if echo "$commit_info" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("valid" "commits" "total_commits" "latest_commit")
    for field in "${required_fields[@]}"; do
        if echo "$commit_info" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证提交数量
    local total_commits
    total_commits=$(echo "$commit_info" | jq '.total_commits')
    if [[ "$total_commits" == "2" ]]; then
        echo "✅ 正确统计提交数量"
    else
        echo "❌ 提交数量统计错误：$total_commits"
        return 1
    fi
}

# 测试：epic_check_safe_to_merge
test_epic_check_safe_to_merge() {
    print_test_header "测试 epic_check_safe_to_merge - 检查Epic是否可安全合并"
    
    setup_test_repo
    
    # 创建安全的Epic分支（只包含roadmap）
    git checkout -b epic-safe-merge-e develop >/dev/null 2>&1
    
    mkdir -p docs/epic_roadmap
    echo "# Epic: [safe-merge]" > docs/epic_roadmap/epic-safe-merge-roadmap.md
    git add docs/epic_roadmap/epic-safe-merge-roadmap.md
    git commit -m "添加roadmap" >/dev/null 2>&1
    
    # 测试安全的Epic分支
    if epic_check_safe_to_merge "epic-safe-merge-e" "$TEST_REPO"; then
        echo "✅ 安全的Epic分支正确通过检查"
    else
        echo "❌ 安全的Epic分支未通过检查"
        return 1
    fi
    
    # 创建不安全的Epic分支（包含代码文件）
    git checkout -b epic-unsafe-merge-e develop >/dev/null 2>&1
    
    mkdir -p docs/epic_roadmap src
    echo "# Epic: [unsafe-merge]" > docs/epic_roadmap/epic-unsafe-merge-roadmap.md
    echo "code" > src/app.js
    git add .
    git commit -m "添加roadmap和代码" >/dev/null 2>&1
    
    # 测试不安全的Epic分支
    if ! epic_check_safe_to_merge "epic-unsafe-merge-e" "$TEST_REPO"; then
        echo "✅ 不安全的Epic分支正确被拒绝"
    else
        echo "❌ 不安全的Epic分支错误通过检查"
        return 1
    fi
}

# 测试：epic_get_validation_report
test_epic_get_validation_report() {
    print_test_header "测试 epic_get_validation_report - 获取Epic验证报告"
    
    setup_test_repo
    
    # 测试不存在的分支
    local report
    report=$(epic_get_validation_report "nonexistent-branch" "$TEST_REPO")
    
    if echo "$report" | jq -e '.valid == false' >/dev/null 2>&1; then
        echo "✅ 不存在分支正确返回invalid"
    else
        echo "❌ 不存在分支返回结果不正确"
        return 1
    fi
    
    # 创建完全合规的Epic分支
    git checkout -b epic-validation-report-e develop >/dev/null 2>&1
    
    mkdir -p docs/epic_roadmap
    echo "# Epic: [validation-report]" > docs/epic_roadmap/epic-validation-report-roadmap.md
    git add docs/epic_roadmap/epic-validation-report-roadmap.md
    git commit -m "添加roadmap" >/dev/null 2>&1
    
    # 测试完全合规的分支
    report=$(epic_get_validation_report "epic-validation-report-e" "$TEST_REPO")
    
    # 验证JSON格式
    if echo "$report" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("valid" "epic_name" "branch_naming" "roadmap_only" "file_types_valid" "roadmap_complete" "safe_to_merge")
    for field in "${required_fields[@]}"; do
        if echo "$report" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证Epic名称提取
    local epic_name
    epic_name=$(echo "$report" | jq -r '.epic_name')
    if [[ "$epic_name" == "validation-report" ]]; then
        echo "✅ 正确提取Epic名称"
    else
        echo "❌ Epic名称提取错误：$epic_name"
        return 1
    fi
    
    # 验证各项检查结果
    local branch_naming roadmap_only safe_to_merge
    branch_naming=$(echo "$report" | jq -r '.branch_naming')
    roadmap_only=$(echo "$report" | jq -r '.roadmap_only')
    safe_to_merge=$(echo "$report" | jq -r '.safe_to_merge')
    
    if [[ "$branch_naming" == "true" ]]; then
        echo "✅ 分支命名检查正确"
    else
        echo "❌ 分支命名检查错误：$branch_naming"
        return 1
    fi
    
    if [[ "$roadmap_only" == "true" ]]; then
        echo "✅ roadmap专用检查正确"
    else
        echo "❌ roadmap专用检查错误：$roadmap_only"
        return 1
    fi
    
    if [[ "$safe_to_merge" == "true" ]]; then
        echo "✅ 安全合并检查正确"
    else
        echo "❌ 安全合并检查错误：$safe_to_merge"
        return 1
    fi
}

# 运行所有测试
run_test "epic_validate_branch_naming" "test_epic_validate_branch_naming"
run_test "epic_extract_name_from_branch" "test_epic_extract_name_from_branch"
run_test "epic_check_roadmap_only" "test_epic_check_roadmap_only"
run_test "epic_validate_commit_files" "test_epic_validate_commit_files"
run_test "epic_get_modified_files" "test_epic_get_modified_files"
run_test "epic_validate_roadmap_completeness" "test_epic_validate_roadmap_completeness"
run_test "epic_get_commit_info" "test_epic_get_commit_info"
run_test "epic_check_safe_to_merge" "test_epic_check_safe_to_merge"
run_test "epic_get_validation_report" "test_epic_get_validation_report"

print_test_summary