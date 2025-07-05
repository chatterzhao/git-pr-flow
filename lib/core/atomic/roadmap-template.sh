#!/bin/bash
# GPF Core - Roadmap Template Atomic Methods
# Roadmap模板原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 生成Epic roadmap模板内容
# 参数：(epic_name, base_branch)
# 返回：roadmap模板内容
roadmap_generate_template() {
    local epic_name="$1"
    local base_branch="$2"
    local creation_time="${3:-$(date '+%Y-%m-%d %H:%M:%S')}"
    
    cat << EOF
# Epic: [$epic_name] 

## Epic概述
- **应用背景**: 
- **Epic目标**: 
- **预期价值**: 

## 子Feature规划
1. **$epic_name-feature-1** - 功能描述1 ⏳ **待实现**
   - **功能描述**: 
   - **验收标准**: 
     - ❌ 标准1
     - ❌ 标准2
     - ❌ 标准3
   - **优先级**: P0
   - **预估工作量**: M（3-5天）
   - **状态**: 尚未开始

2. **$epic_name-feature-2** - 功能描述2 ⏳ **待实现**
   - **功能描述**: 
   - **验收标准**: 
     - ❌ 标准1
     - ❌ 标准2
     - ❌ 标准3
   - **优先级**: P1
   - **预估工作量**: L（5-7天）
   - **状态**: 尚未开始

## 技术要求
- **依赖组件**: 
- **性能要求**: 
- **安全要求**: 
- **兼容性要求**: 
- **遵循文档**: 

## 验收定义 (Definition of Done)
- [ ] 所有子Feature完成并通过测试
- [ ] 单元测试覆盖率>90%
- [ ] 集成测试覆盖率>85%
- [ ] 性能测试通过所有基准
- [ ] 跨平台兼容性验证通过
- [ ] 代码审查通过
- [ ] 文档完整且准确

## 开发计划
- **基础分支**: $base_branch
- **Epic分支**: epic-$epic_name-e
- **创建时间**: $creation_time
- **预计完成**: 

## Feature开发顺序
1. **Week 1**: 
2. **Week 2**: 
3. **集成测试**: 
4. **PR提交**: 

## 📊 当前进度状态
- **总体完成度**: 0%
- **已完成**: 
- **正在进行**: 
- **下一步**: 
- **里程碑**: 
  - ⏳ $creation_time - Epic创建和roadmap规划
EOF
}

# 获取Epic信息结构
# 参数：(epic_name)
# 返回：JSON格式的Epic信息结构
roadmap_get_epic_info() {
    local epic_name="$1"
    
    cat << EOF
{
    "epic_name": "$epic_name",
    "epic_branch": "epic-$epic_name-e",
    "roadmap_file": "docs/epic_roadmap/epic-$epic_name-roadmap.md",
    "features": [],
    "status": "planning",
    "progress": 0
}
EOF
}

# 验证roadmap文件路径格式
# 参数：(epic_name, project_root)
# 返回：0（有效）或1（无效）
roadmap_validate_path() {
    local epic_name="$1"
    local project_root="$2"
    
    # 检查Epic名称格式
    if [[ ! "$epic_name" =~ ^[a-z0-9_-]+$ ]]; then
        return 1
    fi
    
    # 检查项目根目录是否存在
    if [[ ! -d "$project_root" ]]; then
        return 1
    fi
    
    # 检查docs目录路径
    local docs_dir="$project_root/docs"
    local epic_roadmap_dir="$docs_dir/epic_roadmap"
    
    if [[ ! -d "$docs_dir" ]]; then
        return 1
    fi
    
    return 0
}

# 生成roadmap文件路径
# 参数：(epic_name, project_root)
# 返回：roadmap文件的完整路径
roadmap_generate_file_path() {
    local epic_name="$1"
    local project_root="$2"
    
    echo "$project_root/docs/epic_roadmap/epic-$epic_name-roadmap.md"
}

# 检查roadmap文件是否存在
# 参数：(epic_name, project_root)
# 返回：0（存在）或1（不存在）
roadmap_file_exists() {
    local epic_name="$1"
    local project_root="$2"
    
    local roadmap_file
    roadmap_file=$(roadmap_generate_file_path "$epic_name" "$project_root")
    
    [[ -f "$roadmap_file" ]]
}

# 创建roadmap目录结构
# 参数：(project_root)
# 返回：0（成功）或1（失败）
roadmap_create_directory_structure() {
    local project_root="$1"
    
    local docs_dir="$project_root/docs"
    local epic_roadmap_dir="$docs_dir/epic_roadmap"
    
    # 创建docs目录（如果不存在）
    if [[ ! -d "$docs_dir" ]]; then
        mkdir -p "$docs_dir" || return 1
    fi
    
    # 创建epic_roadmap目录（如果不存在）
    if [[ ! -d "$epic_roadmap_dir" ]]; then
        mkdir -p "$epic_roadmap_dir" || return 1
    fi
    
    return 0
}

# 解析roadmap文件获取Epic状态
# 参数：(roadmap_file_path)
# 返回：JSON格式的Epic状态信息
roadmap_parse_epic_status() {
    local roadmap_file="$1"
    
    if [[ ! -f "$roadmap_file" ]]; then
        cat << EOF
{
    "exists": false,
    "epic_name": null,
    "features": [],
    "progress": 0,
    "status": "not_found",
    "error": "Roadmap file not found"
}
EOF
        return 1
    fi
    
    # 提取Epic名称
    local epic_name
    epic_name=$(grep -E '^# Epic: \[' "$roadmap_file" | sed -E 's/^# Epic: \[([^]]+)\].*/\1/' || echo "unknown")
    
    # 统计Feature数量和完成状态
    local total_features completed_features
    total_features=$(grep -c '^[0-9]*\.' "$roadmap_file" 2>/dev/null | tr -d '\n' || echo "0")
    completed_features=$(grep -c '✅ \*\*已完成\*\*' "$roadmap_file" 2>/dev/null | tr -d '\n' || echo "0")
    
    # 计算进度百分比
    local progress=0
    if [[ "$total_features" -gt 0 ]]; then
        progress=$((completed_features * 100 / total_features))
    fi
    
    # 确定状态
    local status="planning"
    if [[ "$completed_features" -eq "$total_features" && "$total_features" -gt 0 ]]; then
        status="completed"
    elif [[ "$completed_features" -gt 0 ]]; then
        status="in_progress"
    fi
    
    cat << EOF
{
    "exists": true,
    "epic_name": "$epic_name",
    "total_features": $total_features,
    "completed_features": $completed_features,
    "progress": $progress,
    "status": "$status"
}
EOF
}

# 生成Feature模板
# 参数：(feature_name, epic_name)
# 返回：Feature模板内容
roadmap_generate_feature_template() {
    local feature_name="$1"
    local epic_name="$2"
    local priority="${3:-P1}"
    local workload="${4:-M（3-5天）}"
    
    cat << EOF
**$epic_name-$feature_name** - 功能描述 ⏳ **待实现**
   - **功能描述**: 
   - **验收标准**: 
     - ❌ 标准1
     - ❌ 标准2
     - ❌ 标准3
   - **优先级**: $priority
   - **预估工作量**: $workload
   - **状态**: 尚未开始
EOF
}

# 验证roadmap文件格式
# 参数：(roadmap_file_path)
# 返回：0（格式正确）或1（格式错误）
roadmap_validate_format() {
    local roadmap_file="$1"
    
    if [[ ! -f "$roadmap_file" ]]; then
        return 1
    fi
    
    # 检查必需的章节标题
    local required_sections=(
        "# Epic:"
        "## Epic概述"
        "## 子Feature规划"
        "## 验收定义"
        "## 开发计划"
    )
    
    local missing_sections=()
    for section in "${required_sections[@]}"; do
        if ! grep -q "^$section" "$roadmap_file"; then
            missing_sections+=("$section")
        fi
    done
    
    # 如果有缺失的章节，返回错误
    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# 提取roadmap文件中的Epic名称
# 参数：(roadmap_file_path)
# 返回：Epic名称 或 空字符串（未找到）
roadmap_extract_epic_name() {
    local roadmap_file="$1"
    
    if [[ ! -f "$roadmap_file" ]]; then
        echo ""
        return 1
    fi
    
    grep -E '^# Epic: \[' "$roadmap_file" | sed -E 's/^# Epic: \[([^]]+)\].*/\1/' || echo ""
}