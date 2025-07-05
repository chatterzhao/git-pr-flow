#!/bin/bash
# GPF Core - Roadmap Template Atomic Methods Tests
# 测试 roadmap-template.sh 中的所有原子方法

set -euo pipefail

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/../../test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/core/atomic/roadmap-template.sh"

# 测试目录设置
TEST_DIR="/tmp/test_roadmap_$$"
mkdir -p "$TEST_DIR"

# 清理函数
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 测试：roadmap_generate_template
test_roadmap_generate_template() {
    print_test_header "测试 roadmap_generate_template - 生成Epic roadmap模板"
    
    local template
    template=$(roadmap_generate_template "test-epic" "develop" "2024-01-01 10:00:00")
    
    # 检查模板是否包含必要内容
    if [[ "$template" =~ "# Epic: [test-epic]" ]]; then
        echo "✅ 模板包含正确的Epic标题"
    else
        echo "❌ 模板不包含正确的Epic标题"
        return 1
    fi
    
    if [[ "$template" =~ "## Epic概述" ]]; then
        echo "✅ 模板包含Epic概述章节"
    else
        echo "❌ 模板不包含Epic概述章节"
        return 1
    fi
    
    if [[ "$template" =~ "## 子Feature规划" ]]; then
        echo "✅ 模板包含子Feature规划章节"
    else
        echo "❌ 模板不包含子Feature规划章节"
        return 1
    fi
    
    if [[ "$template" =~ "epic-test-epic-e" ]]; then
        echo "✅ 模板包含正确的Epic分支名"
    else
        echo "❌ 模板不包含正确的Epic分支名"
        return 1
    fi
    
    if [[ "$template" =~ "develop" ]]; then
        echo "✅ 模板包含基础分支信息"
    else
        echo "❌ 模板不包含基础分支信息"
        return 1
    fi
    
    if [[ "$template" =~ "2024-01-01 10:00:00" ]]; then
        echo "✅ 模板包含创建时间"
    else
        echo "❌ 模板不包含创建时间"
        return 1
    fi
}

# 测试：roadmap_get_epic_info
test_roadmap_get_epic_info() {
    print_test_header "测试 roadmap_get_epic_info - 获取Epic信息结构"
    
    local epic_info
    epic_info=$(roadmap_get_epic_info "test-epic")
    
    # 验证JSON格式
    if echo "$epic_info" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证必需字段
    local required_fields=("epic_name" "epic_branch" "roadmap_file" "features" "status" "progress")
    for field in "${required_fields[@]}"; do
        if echo "$epic_info" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
            echo "✅ 包含必需字段：$field"
        else
            echo "❌ 缺少必需字段：$field"
            return 1
        fi
    done
    
    # 验证字段值
    local epic_name epic_branch
    epic_name=$(echo "$epic_info" | jq -r '.epic_name')
    epic_branch=$(echo "$epic_info" | jq -r '.epic_branch')
    
    if [[ "$epic_name" == "test-epic" ]]; then
        echo "✅ epic_name字段正确"
    else
        echo "❌ epic_name字段不正确：$epic_name"
        return 1
    fi
    
    if [[ "$epic_branch" == "epic-test-epic-e" ]]; then
        echo "✅ epic_branch字段正确"
    else
        echo "❌ epic_branch字段不正确：$epic_branch"
        return 1
    fi
}

# 测试：roadmap_validate_path
test_roadmap_validate_path() {
    print_test_header "测试 roadmap_validate_path - 验证roadmap路径"
    
    # 创建测试目录结构
    mkdir -p "$TEST_DIR/docs"
    
    # 测试有效路径
    if roadmap_validate_path "valid-epic" "$TEST_DIR"; then
        echo "✅ 有效路径验证通过"
    else
        echo "❌ 有效路径验证失败"
        return 1
    fi
    
    # 测试无效Epic名称
    if ! roadmap_validate_path "Invalid-Epic!" "$TEST_DIR"; then
        echo "✅ 无效Epic名称正确被拒绝"
    else
        echo "❌ 无效Epic名称错误通过验证"
        return 1
    fi
    
    # 测试不存在的项目根目录
    if ! roadmap_validate_path "valid-epic" "/nonexistent/path"; then
        echo "✅ 不存在的项目根目录正确被拒绝"
    else
        echo "❌ 不存在的项目根目录错误通过验证"
        return 1
    fi
    
    # 测试缺少docs目录的情况
    local test_dir_no_docs="$TEST_DIR/no_docs"
    mkdir -p "$test_dir_no_docs"
    if ! roadmap_validate_path "valid-epic" "$test_dir_no_docs"; then
        echo "✅ 缺少docs目录正确被拒绝"
    else
        echo "❌ 缺少docs目录错误通过验证"
        return 1
    fi
}

# 测试：roadmap_generate_file_path
test_roadmap_generate_file_path() {
    print_test_header "测试 roadmap_generate_file_path - 生成roadmap文件路径"
    
    local file_path
    file_path=$(roadmap_generate_file_path "test-epic" "$TEST_DIR")
    
    local expected_path="$TEST_DIR/docs/epic_roadmap/epic-test-epic-roadmap.md"
    if [[ "$file_path" == "$expected_path" ]]; then
        echo "✅ 生成的文件路径正确"
    else
        echo "❌ 生成的文件路径不正确：$file_path"
        echo "   期望：$expected_path"
        return 1
    fi
}

# 测试：roadmap_file_exists
test_roadmap_file_exists() {
    print_test_header "测试 roadmap_file_exists - 检查roadmap文件存在性"
    
    # 测试不存在的文件
    if ! roadmap_file_exists "nonexistent-epic" "$TEST_DIR"; then
        echo "✅ 正确检测到不存在的roadmap文件"
    else
        echo "❌ 错误地认为不存在的roadmap文件存在"
        return 1
    fi
    
    # 创建测试文件
    mkdir -p "$TEST_DIR/docs/epic_roadmap"
    touch "$TEST_DIR/docs/epic_roadmap/epic-test-epic-roadmap.md"
    
    # 测试存在的文件
    if roadmap_file_exists "test-epic" "$TEST_DIR"; then
        echo "✅ 正确检测到存在的roadmap文件"
    else
        echo "❌ 未能检测到存在的roadmap文件"
        return 1
    fi
}

# 测试：roadmap_create_directory_structure
test_roadmap_create_directory_structure() {
    print_test_header "测试 roadmap_create_directory_structure - 创建目录结构"
    
    local test_project="$TEST_DIR/new_project"
    mkdir -p "$test_project"
    
    # 测试创建目录结构
    if roadmap_create_directory_structure "$test_project"; then
        echo "✅ 成功创建目录结构"
    else
        echo "❌ 创建目录结构失败"
        return 1
    fi
    
    # 验证目录是否创建
    if [[ -d "$test_project/docs" ]]; then
        echo "✅ docs目录创建成功"
    else
        echo "❌ docs目录未创建"
        return 1
    fi
    
    if [[ -d "$test_project/docs/epic_roadmap" ]]; then
        echo "✅ epic_roadmap目录创建成功"
    else
        echo "❌ epic_roadmap目录未创建"
        return 1
    fi
    
    # 测试重复创建（应该不出错）
    if roadmap_create_directory_structure "$test_project"; then
        echo "✅ 重复创建目录结构不出错"
    else
        echo "❌ 重复创建目录结构出错"
        return 1
    fi
}

# 测试：roadmap_parse_epic_status
test_roadmap_parse_epic_status() {
    print_test_header "测试 roadmap_parse_epic_status - 解析Epic状态"
    
    # 测试不存在的文件
    local status
    status=$(roadmap_parse_epic_status "/nonexistent/file.md")
    
    if echo "$status" | jq -e '.exists == false' >/dev/null 2>&1; then
        echo "✅ 不存在文件正确返回exists=false"
    else
        echo "❌ 不存在文件返回值不正确"
        return 1
    fi
    
    # 创建测试roadmap文件
    local test_roadmap="$TEST_DIR/test-roadmap.md"
    cat > "$test_roadmap" << 'EOF'
# Epic: [test-epic] 测试Epic

## Epic概述

## 子Feature规划
1. **test-epic-feature-1** - 功能1 ✅ **已完成**
2. **test-epic-feature-2** - 功能2 ⏳ **待实现**
3. **test-epic-feature-3** - 功能3 ⏳ **待实现**
EOF
    
    # 测试解析存在的文件
    status=$(roadmap_parse_epic_status "$test_roadmap")
    
    # 验证JSON格式
    if echo "$status" | jq . >/dev/null 2>&1; then
        echo "✅ 返回有效的JSON格式"
    else
        echo "❌ 返回无效的JSON格式"
        return 1
    fi
    
    # 验证字段值
    local exists epic_name total_features completed_features progress
    exists=$(echo "$status" | jq -r '.exists')
    epic_name=$(echo "$status" | jq -r '.epic_name')
    total_features=$(echo "$status" | jq -r '.total_features')
    completed_features=$(echo "$status" | jq -r '.completed_features')
    progress=$(echo "$status" | jq -r '.progress')
    
    if [[ "$exists" == "true" ]]; then
        echo "✅ 正确识别文件存在"
    else
        echo "❌ 未正确识别文件存在"
        return 1
    fi
    
    if [[ "$epic_name" == "test-epic" ]]; then
        echo "✅ 正确提取Epic名称"
    else
        echo "❌ Epic名称提取错误：$epic_name"
        return 1
    fi
    
    if [[ "$total_features" == "3" ]]; then
        echo "✅ 正确统计总Feature数量"
    else
        echo "❌ 总Feature数量统计错误：$total_features"
        return 1
    fi
    
    if [[ "$completed_features" == "1" ]]; then
        echo "✅ 正确统计已完成Feature数量"
    else
        echo "❌ 已完成Feature数量统计错误：$completed_features"
        return 1
    fi
    
    if [[ "$progress" == "33" ]]; then
        echo "✅ 正确计算进度百分比"
    else
        echo "❌ 进度百分比计算错误：$progress"
        return 1
    fi
}

# 测试：roadmap_generate_feature_template
test_roadmap_generate_feature_template() {
    print_test_header "测试 roadmap_generate_feature_template - 生成Feature模板"
    
    local feature_template
    feature_template=$(roadmap_generate_feature_template "login" "auth" "P0" "L（5-7天）")
    
    # 检查模板内容
    if [[ "$feature_template" =~ "**auth-login**" ]]; then
        echo "✅ 模板包含正确的Feature名称"
    else
        echo "❌ 模板不包含正确的Feature名称"
        return 1
    fi
    
    if [[ "$feature_template" =~ "**优先级**: P0" ]]; then
        echo "✅ 模板包含正确的优先级"
    else
        echo "❌ 模板不包含正确的优先级"
        return 1
    fi
    
    if [[ "$feature_template" =~ "**预估工作量**: L（5-7天）" ]]; then
        echo "✅ 模板包含正确的工作量"
    else
        echo "❌ 模板不包含正确的工作量"
        return 1
    fi
    
    if [[ "$feature_template" =~ "⏳ **待实现**" ]]; then
        echo "✅ 模板包含正确的状态标识"
    else
        echo "❌ 模板不包含正确的状态标识"
        return 1
    fi
}

# 测试：roadmap_validate_format
test_roadmap_validate_format() {
    print_test_header "测试 roadmap_validate_format - 验证roadmap格式"
    
    # 测试不存在的文件
    if ! roadmap_validate_format "/nonexistent/file.md"; then
        echo "✅ 不存在文件正确返回格式无效"
    else
        echo "❌ 不存在文件错误返回格式有效"
        return 1
    fi
    
    # 创建格式正确的roadmap文件
    local valid_roadmap="$TEST_DIR/valid-roadmap.md"
    cat > "$valid_roadmap" << 'EOF'
# Epic: [test-epic]

## Epic概述

## 子Feature规划

## 验收定义

## 开发计划
EOF
    
    # 测试格式正确的文件
    if roadmap_validate_format "$valid_roadmap"; then
        echo "✅ 格式正确的文件通过验证"
    else
        echo "❌ 格式正确的文件未通过验证"
        return 1
    fi
    
    # 创建格式错误的roadmap文件（缺少必需章节）
    local invalid_roadmap="$TEST_DIR/invalid-roadmap.md"
    cat > "$invalid_roadmap" << 'EOF'
# Epic: [test-epic]

## Epic概述
EOF
    
    # 测试格式错误的文件
    if ! roadmap_validate_format "$invalid_roadmap"; then
        echo "✅ 格式错误的文件正确被拒绝"
    else
        echo "❌ 格式错误的文件错误通过验证"
        return 1
    fi
}

# 测试：roadmap_extract_epic_name
test_roadmap_extract_epic_name() {
    print_test_header "测试 roadmap_extract_epic_name - 提取Epic名称"
    
    # 测试不存在的文件
    local epic_name
    epic_name=$(roadmap_extract_epic_name "/nonexistent/file.md")
    
    if [[ -z "$epic_name" ]]; then
        echo "✅ 不存在文件正确返回空Epic名称"
    else
        echo "❌ 不存在文件返回了Epic名称：$epic_name"
        return 1
    fi
    
    # 创建包含Epic名称的文件
    local test_file="$TEST_DIR/epic-name-test.md"
    echo "# Epic: [test-epic-name] 测试Epic" > "$test_file"
    
    epic_name=$(roadmap_extract_epic_name "$test_file")
    
    if [[ "$epic_name" == "test-epic-name" ]]; then
        echo "✅ 正确提取Epic名称"
    else
        echo "❌ Epic名称提取错误：$epic_name"
        return 1
    fi
    
    # 测试格式错误的文件
    local invalid_file="$TEST_DIR/invalid-epic.md"
    echo "这是一个无效的文件" > "$invalid_file"
    
    epic_name=$(roadmap_extract_epic_name "$invalid_file")
    
    if [[ -z "$epic_name" ]]; then
        echo "✅ 格式错误的文件正确返回空Epic名称"
    else
        echo "❌ 格式错误的文件返回了Epic名称：$epic_name"
        return 1
    fi
}

# 运行所有测试
run_test "roadmap_generate_template" "test_roadmap_generate_template"
run_test "roadmap_get_epic_info" "test_roadmap_get_epic_info"
run_test "roadmap_validate_path" "test_roadmap_validate_path"
run_test "roadmap_generate_file_path" "test_roadmap_generate_file_path"
run_test "roadmap_file_exists" "test_roadmap_file_exists"
run_test "roadmap_create_directory_structure" "test_roadmap_create_directory_structure"
run_test "roadmap_parse_epic_status" "test_roadmap_parse_epic_status"
run_test "roadmap_generate_feature_template" "test_roadmap_generate_feature_template"
run_test "roadmap_validate_format" "test_roadmap_validate_format"
run_test "roadmap_extract_epic_name" "test_roadmap_extract_epic_name"

print_test_summary