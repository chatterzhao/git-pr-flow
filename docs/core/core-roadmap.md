# GPF 核心公共组件设计 - Epic Roadmap管理

> 📖 **相关文档**: [主文档](../../README.md) | [架构设计](../ARCHITECTURE.md) | [命令详细](../COMMANDS.md) | [术语表](../术语表.md) | [核心组件索引](../CORE-COMPONENTS.md)

## 设计原则

基于用户的架构哲学："基本方法在 core 文档，并且多个命令是一样的方法，也在core里将多个基本方法组装为高级一点的方法。command文档根据具体命令调用通用或某个命令不一样的调用core 方法扩展加一些自有方法组装为该命令所需方法"

1. **单一职责**：每个组件只负责一个明确的功能域
2. **无副作用**：纯函数设计，输入确定输出确定
3. **错误透明**：清晰的错误传播和处理机制
4. **测试友好**：每个函数都可以独立测试
5. **平台兼容**：跨平台文件系统和路径处理
6. **职责分离**：core提供基础工具，command组合使用
7. **🆕 GitHub集成**：统一的GitHub CLI检查和PR状态管理

---

## 6. roadmap.sh - Epic Roadmap管理

### 核心功能
管理Epic的roadmap文件生成、验证和Epic分支保护机制。

### 数据结构

```bash
# Roadmap信息对象
RoadmapInfo = {
    epic_name: "auth"                           # Epic名称
    roadmap_path: "docs/epic_roadmap/epic-auth-e-roadmap.md"  # Roadmap文件路径  
    template_status: "template" | "customized" | "committed"  # 模板状态
    validation_status: "valid" | "invalid"      # 验证状态
    commit_status: "uncommitted" | "committed"  # Git提交状态
}
```

### Roadmap模板生成

```bash
# 生成Epic roadmap模板
generate_roadmap_template() {
    local user_input="$1"                          # 用户原始输入，可能包含前缀后缀
    local base_branch="$2"
    
    # ✅ 使用标准的前缀后缀处理方法，避免重复拼接
    local full_branch_name
    full_branch_name=$(transform_input_to_epic_branch "$user_input")
    
    # 从完整分支名提取纯净Epic名称用于模板内容
    local clean_epic_name
    clean_epic_name=$(strip_epic_prefix_from_input "$user_input")
    clean_epic_name=$(strip_suffix_from_input "$clean_epic_name")
    
    local roadmap_path="docs/epic_roadmap/${full_branch_name}-roadmap.md"
    
    # 创建目录
    mkdir -p "$(dirname "$roadmap_path")"
    
    # 生成智能模板
    cat > "$roadmap_path" << EOF
# Epic: [${clean_epic_name}] 功能模块

## Epic概述
- **应用背景**: [描述整个应用是什么，解决什么问题]
- **Epic目标**: [当前Epic要解决的核心问题和功能范围]
- **预期价值**: [Epic完成后带来的业务价值和用户价值]

## 子Feature规划
1. **${clean_epic_name}-[feature-name]** - [功能简述]
   - **功能描述**: [详细描述这个子功能做什么]
   - **验收标准**: [具体的AC条件，如：用户可以xxx，系统应该xxx]
   - **优先级**: [P0/P1/P2]
   - **预估工作量**: [S/M/L 或具体天数]

2. **${clean_epic_name}-[feature-name]** - [功能简述]
   - **功能描述**: [详细描述]
   - **验收标准**: [具体的AC条件]
   - **优先级**: [P0/P1/P2]
   - **预估工作量**: [S/M/L]

## 技术要求
- **依赖组件**: [列出需要的第三方库、内部模块等]
- **性能要求**: [响应时间、并发量等具体指标]
- **安全要求**: [认证、授权、数据保护等]
- **兼容性要求**: [浏览器、设备、API版本等]
- **遵循文档**: [xx规范，xx架构，xx目录下的文档]

## 验收定义 (Definition of Done)
- [ ] [所有子Feature完成并通过测试]
- [ ] [API文档完整]
- [ ] [单元测试覆盖率 > 80%]
- [ ] [性能测试通过]
- [ ] [安全扫描通过]

## 开发计划
- **基础分支**: ${base_branch}
- **Epic分支**: ${full_branch_name}
- **创建时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **预计完成**: [设定目标日期]
EOF

    echo "$roadmap_path"
}

# 测试用例说明（验证前缀后缀处理）
# 用户输入 "auth"           → roadmap文件: docs/epic_roadmap/epic-auth-e-roadmap.md
# 用户输入 "epic-auth"      → roadmap文件: docs/epic_roadmap/epic-auth-e-roadmap.md  
# 用户输入 "epic-auth-e"    → roadmap文件: docs/epic_roadmap/epic-auth-e-roadmap.md
# 用户输入 "auth-e"         → roadmap文件: docs/epic_roadmap/epic-auth-e-roadmap.md
```

### Roadmap验证

```bash
# 验证roadmap是否完善
validate_roadmap_completeness() {
    local roadmap_path="$1"
    
    if [[ ! -f "$roadmap_path" ]]; then
        echo "roadmap_not_exists"
        return 1
    fi
    
    # 检查是否还有未填充的占位符
    local placeholder_count=$(grep -c '\[.*\]' "$roadmap_path" || true)
    
    if [[ $placeholder_count -gt 0 ]]; then
        echo "template_not_customized:$placeholder_count"
        return 1
    fi
    
    # 检查是否已提交到Git
    if ! git ls-files --error-unmatch "$roadmap_path" >/dev/null 2>&1; then
        echo "not_tracked"
        return 1
    fi
    
    if git diff --quiet "$roadmap_path" && git diff --cached --quiet "$roadmap_path"; then
        echo "committed"
        return 0
    else
        echo "uncommitted"
        return 1
    fi
}

# 获取roadmap详细验证信息
get_roadmap_validation_details() {
    local roadmap_path="$1"
    local validation_result
    validation_result=$(validate_roadmap_completeness "$roadmap_path")
    
    case "$validation_result" in
        "committed")
            echo "✅ Roadmap已完善且已提交"
            return 0
            ;;
        "template_not_customized:"*)
            local count="${validation_result#*:}"
            echo "❌ Roadmap仍有 $count 个未填充的占位符 [...]"
            grep -n '\[.*\]' "$roadmap_path" | head -5
            return 1
            ;;
        "uncommitted")
            echo "⚠️ Roadmap已修改但未提交到Git"
            return 1
            ;;
        "not_tracked")
            echo "❌ Roadmap文件未添加到Git跟踪"
            return 1
            ;;
        "roadmap_not_exists")
            echo "❌ Roadmap文件不存在"
            return 1
            ;;
    esac
}
```

### Epic分支保护

```bash
# 检查Epic分支提交的文件
validate_epic_commit_files() {
    local user_input="$1"                          # 用户输入的Epic名称
    local modified_files
    
    # 获取暂存区的修改文件
    modified_files=$(git diff --cached --name-only)
    
    # ✅ 使用标准的前缀后缀处理方法
    local full_branch_name
    full_branch_name=$(transform_input_to_epic_branch "$user_input")
    
    # 定义允许的roadmap文件模式
    local roadmap_pattern="^docs/epic_roadmap/${full_branch_name}-roadmap\.md$"
    
    local non_roadmap_files=()
    while IFS= read -r file; do
        if [[ -n "$file" ]] && ! [[ "$file" =~ $roadmap_pattern ]]; then
            non_roadmap_files+=("$file")
        fi
    done <<< "$modified_files"
    
    if [[ ${#non_roadmap_files[@]} -gt 0 ]]; then
        echo "epic_protection_violation"
        printf '%s\n' "${non_roadmap_files[@]}"
        return 1
    fi
    
    echo "epic_commit_allowed"
    return 0
}

# Epic分支保护主函数
enforce_epic_branch_protection() {
    local current_branch
    current_branch=$(git branch --show-current)
    
    # 检查是否是Epic分支
    if [[ "$current_branch" =~ ^epic-.*-e$ ]]; then
        local epic_name="${current_branch#epic-}"
        epic_name="${epic_name%-e}"
        
        local validation_result
        validation_result=$(validate_epic_commit_files "$epic_name")
        
        if [[ "$validation_result" == "epic_protection_violation" ]]; then
            return 1
        fi
    fi
    
    return 0
}
```

### 组合工作流方法

```bash
# Epic创建完整流程
create_epic_with_roadmap() {
    local user_input="$1"                          # 用户输入的Epic名称
    local base_branch="$2"
    local project_root="$3"
    
    # 获取纯净Epic名称用于提示
    local clean_epic_name
    clean_epic_name=$(strip_epic_prefix_from_input "$user_input")
    clean_epic_name=$(strip_suffix_from_input "$clean_epic_name")
    
    # 1. 创建roadmap（传递用户原始输入给模板生成函数）
    local roadmap_path
    roadmap_path=$(generate_roadmap_template "$user_input" "$base_branch")
    
    # 2. 提示用户完善
    ui_info "📋 已生成Epic roadmap: $roadmap_path"
    ui_info "📝 下一步操作："
    ui_info "   1. 编辑 $roadmap_path 完善Epic规划"
    ui_info "   2. 提交roadmap: git add . && git commit -m \"完善${clean_epic_name} Epic roadmap\""
    ui_info "   3. 创建子Feature: gpf start -ef <feature-name> $clean_epic_name"
    
    return 0
}

# Feature创建前的roadmap检查
validate_epic_ready_for_feature() {
    local user_input="$1"                          # 用户输入的Epic名称
    
    # ✅ 使用标准的前缀后缀处理方法
    local full_branch_name
    full_branch_name=$(transform_input_to_epic_branch "$user_input")
    
    local roadmap_path="docs/epic_roadmap/${full_branch_name}-roadmap.md"
    
    local validation_details
    validation_details=$(get_roadmap_validation_details "$roadmap_path")
    local validation_status=$?
    
    if [[ $validation_status -ne 0 ]]; then
        ui_error "Epic roadmap未完善"
        ui_error "📋 Roadmap状态: $validation_details"
        ui_info ""
        ui_info "💡 解决方案："
        ui_info "   1. 完善roadmap内容: vim $roadmap_path"
        ui_info "   2. 将所有 [占位符] 替换为实际规划内容"
        ui_info "   3. 提交roadmap: git add $roadmap_path && git commit -m \"完善$epic_name Epic roadmap\""
        ui_info "   4. 重新创建子Feature"
        return 1
    fi
    
    ui_success "$validation_details"
    return 0
}
```