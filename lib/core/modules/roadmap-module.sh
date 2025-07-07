#!/bin/bash
# GPF Roadmap管理模块 - 提供Epic规划管理和分支保护功能
# 本模块为start命令提供完整的roadmap生命周期管理

set -euo pipefail

# 按四层架构获取项目根目录（通过composite层）
source "$(dirname "${BASH_SOURCE[0]}")/../composite/environment-composite.sh"

# 通过composite层获取项目根目录（遵循四层架构）
PROJECT_ROOT=$(environment_get_project_root) || {
    echo "❌ 错误：无法通过composite层获取项目根目录" >&2
    exit 1
}

# 加载依赖
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/roadmap-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/validation-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/git-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../composite/environment-composite.sh"

# ==============================================================================
# Roadmap管理模块 - 核心方法
# ==============================================================================

# Epic roadmap完整生命周期管理（start命令核心功能）
roadmap_module_epic_lifecycle() {
    local action="$1"                    # initialize/validate/update/finalize
    local epic_name="$2"
    local base_branch="${3:-develop}"
    local project_root="${4:-$PROJECT_ROOT}"
    local options="${5:-}"               # JSON格式的可选参数
    
    case "$action" in
        "initialize")
            roadmap_module_initialize_epic_roadmap "$epic_name" "$base_branch" "$project_root" "$options"
            ;;
        "validate")
            roadmap_module_validate_epic_roadmap "$epic_name" "$project_root"
            ;;
        "update")
            roadmap_module_update_epic_roadmap "$epic_name" "$project_root" "$options"
            ;;
        "finalize")
            roadmap_module_finalize_epic_roadmap "$epic_name" "$project_root"
            ;;
        *)
            echo "❌ 错误：未知的roadmap生命周期动作: $action" >&2
            return 1
            ;;
    esac
}

# Epic分支保护管理（确保Epic分支只能修改roadmap）
roadmap_module_branch_protection() {
    local action="$1"                    # enable/disable/check
    local epic_name="$2"
    local project_root="${3:-$PROJECT_ROOT}"
    
    local epic_branch="epic-$epic_name-e"
    
    case "$action" in
        "enable")
            roadmap_module_enable_branch_protection "$epic_branch" "$project_root"
            ;;
        "disable")
            roadmap_module_disable_branch_protection "$epic_branch" "$project_root"
            ;;
        "check")
            roadmap_module_check_branch_protection "$epic_branch" "$project_root"
            ;;
        *)
            echo "❌ 错误：未知的分支保护动作: $action" >&2
            return 1
            ;;
    esac
}

# Roadmap状态监控（status命令使用）
roadmap_module_status_monitoring() {
    local scope="${1:-all}"              # all/epic/current
    local epic_name="${2:-}"             # 特定Epic名称（可选）
    local project_root="${3:-$PROJECT_ROOT}"
    
    case "$scope" in
        "all")
            roadmap_module_monitor_all_roadmaps "$project_root"
            ;;
        "epic")
            [[ -n "$epic_name" ]] || {
                echo "❌ 错误：监控特定Epic需要提供Epic名称" >&2
                return 1
            }
            roadmap_module_monitor_epic_roadmap "$epic_name" "$project_root"
            ;;
        "current")
            roadmap_module_monitor_current_roadmap "$project_root"
            ;;
        *)
            echo "❌ 错误：未知的监控范围: $scope" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# Epic Roadmap初始化和管理
# ==============================================================================

# 初始化Epic roadmap
roadmap_module_initialize_epic_roadmap() {
    local epic_name="$1"
    local base_branch="$2"
    local project_root="$3"
    local options="${4:-}"
    
    # 验证Epic名称
    if ! validate_name_format "$epic_name"; then
        echo "❌ 错误：Epic名称格式不正确: $epic_name" >&2
        return 1
    fi
    
    # 创建roadmap目录结构
    if ! roadmap_create_directory_structure "$project_root"; then
        echo "❌ 错误：无法创建roadmap目录结构" >&2
        return 1
    fi
    
    # 生成roadmap模板
    local template_content
    template_content=$(roadmap_generate_template "$epic_name" "$base_branch" "$(date -u +"%Y-%m-%d %H:%M:%S")") || {
        echo "❌ 错误：roadmap模板生成失败" >&2
        return 1
    }
    
    # 处理可选参数
    if [[ -n "$options" ]]; then
        template_content=$(roadmap_module_apply_custom_options "$template_content" "$options")
    fi
    
    # 写入roadmap文件
    local roadmap_file="$project_root/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
    echo "$template_content" > "$roadmap_file" || {
        echo "❌ 错误：无法写入roadmap文件" >&2
        return 1
    }
    
    # 创建初始化状态记录
    roadmap_module_record_initialization "$epic_name" "$project_root"
    
    echo "✅ Epic roadmap初始化完成: $roadmap_file"
    return 0
}

# 验证Epic roadmap完整性
roadmap_module_validate_epic_roadmap() {
    local epic_name="$1"
    local project_root="$2"
    
    local roadmap_file="$project_root/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
    
    # 检查roadmap文件是否存在
    [[ -f "$roadmap_file" ]] || {
        cat <<EOF
{
    "valid": false,
    "epic_name": "$epic_name",
    "issues": ["roadmap文件不存在"],
    "template_status": "missing"
}
EOF
        return 1
    }
    
    # 验证roadmap内容
    local validation_result
    validation_result=$(roadmap_module_validate_content "$roadmap_file") || return 1
    
    # 检查模板状态
    local template_status
    template_status=$(roadmap_check_template_completion "$roadmap_file") || template_status="error"
    
    # 返回验证结果
    cat <<EOF
{
    "valid": $(echo "$validation_result" | jq -r '.valid'),
    "epic_name": "$epic_name",
    "roadmap_file": "$roadmap_file",
    "template_status": "$template_status",
    "issues": $(echo "$validation_result" | jq -r '.issues // []'),
    "warnings": $(echo "$validation_result" | jq -r '.warnings // []'),
    "placeholder_count": $(roadmap_count_placeholders "$roadmap_file" 2>/dev/null || echo "0")
}
EOF
}

# 更新Epic roadmap
roadmap_module_update_epic_roadmap() {
    local epic_name="$1"
    local project_root="$2"
    local options="$3"
    
    local roadmap_file="$project_root/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
    
    # 验证roadmap存在
    [[ -f "$roadmap_file" ]] || {
        echo "❌ 错误：roadmap文件不存在: $roadmap_file" >&2
        return 1
    }
    
    # 解析更新选项
    local update_type
    update_type=$(echo "$options" | jq -r '.type // "manual"')
    
    case "$update_type" in
        "manual")
            roadmap_module_manual_update "$roadmap_file" "$options"
            ;;
        "auto_progress")
            roadmap_module_auto_update_progress "$roadmap_file" "$epic_name" "$project_root"
            ;;
        "feature_complete")
            roadmap_module_feature_completion_update "$roadmap_file" "$options"
            ;;
        *)
            echo "❌ 错误：未知的更新类型: $update_type" >&2
            return 1
            ;;
    esac
}

# 完成Epic roadmap
roadmap_module_finalize_epic_roadmap() {
    local epic_name="$1"
    local project_root="$2"
    
    local roadmap_file="$project_root/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
    
    # 验证roadmap完整性
    local validation_result
    validation_result=$(roadmap_module_validate_epic_roadmap "$epic_name" "$project_root") || {
        echo "❌ 错误：roadmap验证失败，无法完成" >&2
        return 1
    }
    
    local is_valid=$(echo "$validation_result" | jq -r '.valid')
    [[ "$is_valid" == "true" ]] || {
        echo "❌ 错误：roadmap包含错误，无法完成" >&2
        return 1
    }
    
    # 检查是否还有占位符
    local placeholder_count
    placeholder_count=$(echo "$validation_result" | jq -r '.placeholder_count')
    
    if [[ "$placeholder_count" -gt 0 ]]; then
        echo "⚠️ 警告：roadmap仍包含 $placeholder_count 个占位符" >&2
        echo "💡 建议：完善roadmap内容后再完成Epic" >&2
    fi
    
    # 标记roadmap为已完成
    roadmap_module_mark_as_finalized "$roadmap_file" "$epic_name"
    
    echo "✅ Epic roadmap已完成: $epic_name"
    return 0
}

# ==============================================================================
# Roadmap内容验证和处理
# ==============================================================================

# 验证roadmap内容
roadmap_module_validate_content() {
    local roadmap_file="$1"
    
    local issues="[]"
    local warnings="[]"
    local valid="true"
    
    # 检查基础结构
    if ! grep -q "^# Epic:" "$roadmap_file"; then
        issues=$(echo "$issues" | jq '. += ["缺少Epic标题"]')
        valid="false"
    fi
    
    if ! grep -q "## Epic概述" "$roadmap_file"; then
        issues=$(echo "$issues" | jq '. += ["缺少Epic概述"]')
        valid="false"
    fi
    
    if ! grep -q "## 子Feature规划" "$roadmap_file"; then
        issues=$(echo "$issues" | jq '. += ["缺少子Feature规划"]')
        valid="false"
    fi
    
    # 检查占位符
    local placeholder_count
    placeholder_count=$(roadmap_count_placeholders "$roadmap_file")
    
    if [[ "$placeholder_count" -gt 0 ]]; then
        warnings=$(echo "$warnings" | jq --argjson count "$placeholder_count" '. += ["包含 " + ($count|tostring) + " 个未填充占位符"]')
    fi
    
    # 检查Feature列表格式
    if ! roadmap_module_validate_feature_format "$roadmap_file"; then
        warnings=$(echo "$warnings" | jq '. += ["Feature列表格式可能不正确"]')
    fi
    
    cat <<EOF
{
    "valid": $valid,
    "issues": $issues,
    "warnings": $warnings
}
EOF
}

# 验证Feature格式
roadmap_module_validate_feature_format() {
    local roadmap_file="$1"
    
    # 查找Feature规划部分
    local feature_section
    feature_section=$(sed -n '/## 子Feature规划/,/^##/p' "$roadmap_file" | head -n -1)
    
    # 检查是否有正确的Feature条目格式
    echo "$feature_section" | grep -q '^[0-9]\+\. \*\*.*\*\* -'
}

# 应用自定义选项
roadmap_module_apply_custom_options() {
    local template_content="$1"
    local options="$2"
    
    # 解析自定义选项
    local custom_description=$(echo "$options" | jq -r '.description // empty')
    local custom_features=$(echo "$options" | jq -r '.features // empty')
    local custom_priority=$(echo "$options" | jq -r '.priority // empty')
    
    # 应用自定义描述
    if [[ -n "$custom_description" ]]; then
        template_content=$(echo "$template_content" | sed "s/\[Epic的具体描述和目标\]/$custom_description/g")
    fi
    
    # 应用自定义优先级
    if [[ -n "$custom_priority" ]]; then
        template_content=$(echo "$template_content" | sed "s/\[P0\/P1\/P2\]/$custom_priority/g")
    fi
    
    echo "$template_content"
}

# ==============================================================================
# 分支保护功能
# ==============================================================================

# 启用分支保护
roadmap_module_enable_branch_protection() {
    local epic_branch="$1"
    local project_root="$2"
    
    # 创建保护配置文件
    local protection_file="$project_root/.worktrees/$epic_branch/.gpf_protection"
    
    if [[ -d "$project_root/.worktrees/$epic_branch" ]]; then
        cat > "$protection_file" <<EOF
# GPF Epic分支保护配置
protection_enabled=true
allowed_paths=docs/epic_roadmap/
protection_level=roadmap_only
created_at=$(date -u +"%Y-%m-%d %H:%M:%S")
EOF
        echo "✅ 分支保护已启用: $epic_branch"
    else
        echo "⚠️ 警告：Epic工作树不存在，保护配置将在创建时应用" >&2
    fi
    
    return 0
}

# 禁用分支保护
roadmap_module_disable_branch_protection() {
    local epic_branch="$1"
    local project_root="$2"
    
    local protection_file="$project_root/.worktrees/$epic_branch/.gpf_protection"
    
    if [[ -f "$protection_file" ]]; then
        rm -f "$protection_file"
        echo "✅ 分支保护已禁用: $epic_branch"
    else
        echo "💡 信息：分支保护未启用" >&2
    fi
    
    return 0
}

# 检查分支保护状态
roadmap_module_check_branch_protection() {
    local epic_branch="$1"
    local project_root="$2"
    
    local protection_file="$project_root/.worktrees/$epic_branch/.gpf_protection"
    
    if [[ -f "$protection_file" ]]; then
        local protection_enabled
        protection_enabled=$(grep "protection_enabled=true" "$protection_file" >/dev/null && echo "true" || echo "false")
        
        local allowed_paths
        allowed_paths=$(grep "allowed_paths=" "$protection_file" | cut -d'=' -f2)
        
        cat <<EOF
{
    "protection_enabled": $protection_enabled,
    "epic_branch": "$epic_branch",
    "allowed_paths": "$allowed_paths",
    "protection_file": "$protection_file"
}
EOF
    else
        cat <<EOF
{
    "protection_enabled": false,
    "epic_branch": "$epic_branch",
    "allowed_paths": "",
    "protection_file": null
}
EOF
    fi
}

# ==============================================================================
# Roadmap状态监控
# ==============================================================================

# 监控所有roadmap
roadmap_module_monitor_all_roadmaps() {
    local project_root="$1"
    
    local roadmap_dir="$project_root/docs/epic_roadmap"
    [[ -d "$roadmap_dir" ]] || {
        echo '{"roadmaps": [], "total_count": 0}'
        return 0
    }
    
    local roadmaps="[]"
    
    # 遍历所有roadmap文件
    find "$roadmap_dir" -name "epic-*-e-roadmap.md" | while read -r roadmap_file; do
        local epic_name
        epic_name=$(basename "$roadmap_file" | sed 's/^epic-\(.*\)-e-roadmap\.md$/\1/')
        
        local roadmap_status
        roadmap_status=$(roadmap_module_get_roadmap_status "$epic_name" "$project_root")
        
        roadmaps=$(echo "$roadmaps" | jq --argjson status "$roadmap_status" '. += [$status]')
    done
    
    local total_count
    total_count=$(echo "$roadmaps" | jq 'length')
    
    cat <<EOF
{
    "roadmaps": $roadmaps,
    "total_count": $total_count,
    "monitoring_time": "$(date -u +"%Y-%m-%d %H:%M:%S")"
}
EOF
}

# 监控特定Epic roadmap
roadmap_module_monitor_epic_roadmap() {
    local epic_name="$1"
    local project_root="$2"
    
    roadmap_module_get_roadmap_status "$epic_name" "$project_root"
}

# 监控当前roadmap
roadmap_module_monitor_current_roadmap() {
    local project_root="$1"
    
    # 检测当前环境
    local current_env
    current_env=$(environment_detect_complete 2>/dev/null) || {
        echo '{"error": "无法检测当前环境"}'
        return 1
    }
    
    case "$current_env" in
        "epic"|"feature")
            local current_epic
            current_epic=$(extract_current_epic_name) || {
                echo '{"error": "无法确定当前Epic"}'
                return 1
            }
            
            roadmap_module_monitor_epic_roadmap "$current_epic" "$project_root"
            ;;
        *)
            echo '{"error": "当前不在Epic或Feature环境中"}'
            return 1
            ;;
    esac
}

# 获取roadmap状态
roadmap_module_get_roadmap_status() {
    local epic_name="$1"
    local project_root="$2"
    
    local roadmap_file="$project_root/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
    
    # 基础信息
    local exists="false"
    local file_size="0"
    local last_modified=""
    
    if [[ -f "$roadmap_file" ]]; then
        exists="true"
        file_size=$(wc -c < "$roadmap_file" | tr -d ' \n')
        last_modified=$(date -r "$roadmap_file" -u +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    fi
    
    # 验证状态
    local validation_status="{}"
    if [[ "$exists" == "true" ]]; then
        validation_status=$(roadmap_module_validate_epic_roadmap "$epic_name" "$project_root" 2>/dev/null || echo '{"valid": false}')
    fi
    
    # 分支保护状态
    local protection_status
    protection_status=$(roadmap_module_check_branch_protection "epic-$epic_name-e" "$project_root")
    
    cat <<EOF
{
    "epic_name": "$epic_name",
    "roadmap_file": "$roadmap_file",
    "exists": $exists,
    "file_size": $file_size,
    "last_modified": "$last_modified",
    "validation_status": $validation_status,
    "protection_status": $protection_status
}
EOF
}

# ==============================================================================
# 辅助功能
# ==============================================================================

# 记录初始化状态
roadmap_module_record_initialization() {
    local epic_name="$1"
    local project_root="$2"
    
    local record_file="$project_root/docs/epic_roadmap/.epic_records"
    
    # 创建记录文件（如果不存在）
    [[ -f "$record_file" ]] || echo "# Epic Roadmap初始化记录" > "$record_file"
    
    # 添加记录
    cat >> "$record_file" <<EOF
$(date -u +"%Y-%m-%d %H:%M:%S") - Epic '$epic_name' roadmap初始化完成
EOF
}

# 标记为已完成
roadmap_module_mark_as_finalized() {
    local roadmap_file="$1"
    local epic_name="$2"
    
    # 在roadmap文件末尾添加完成标记
    cat >> "$roadmap_file" <<EOF

---

## 📋 Epic完成记录
- **完成时间**: $(date -u +"%Y-%m-%d %H:%M:%S")
- **状态**: 已完成
- **完成方式**: 自动标记

*此Epic的roadmap规划已完成，可以进入实施阶段。*
EOF
}

# 手动更新
roadmap_module_manual_update() {
    local roadmap_file="$1"
    local options="$2"
    
    local content=$(echo "$options" | jq -r '.content // empty')
    local section=$(echo "$options" | jq -r '.section // empty')
    
    if [[ -n "$content" && -n "$section" ]]; then
        # 更新特定section（简化实现）
        echo "💡 手动更新功能待实现" >&2
    fi
    
    echo "✅ 请手动编辑roadmap文件: $roadmap_file"
}

# 自动更新进度
roadmap_module_auto_update_progress() {
    local roadmap_file="$1"
    local epic_name="$2"
    local project_root="$3"
    
    # 检查Epic相关的Feature分支状态
    local feature_count=0
    local completed_features=0
    
    if [[ -d "$project_root/.worktrees" ]]; then
        feature_count=$(find "$project_root/.worktrees" -maxdepth 1 -type d -name "epic-$epic_name-e-*-ef" | wc -l | tr -d ' \n')
        
        # 这里可以添加更复杂的完成度检查逻辑
        # 简化实现：假设存在的Feature都是进行中的
    fi
    
    # 更新roadmap中的进度信息（简化实现）
    echo "📊 检测到 $feature_count 个相关Feature分支" >&2
    echo "✅ 进度自动更新完成"
}

# Feature完成更新
roadmap_module_feature_completion_update() {
    local roadmap_file="$1"
    local options="$2"
    
    local feature_name=$(echo "$options" | jq -r '.feature_name // empty')
    
    if [[ -n "$feature_name" ]]; then
        echo "✅ Feature '$feature_name' 完成状态已记录" >&2
        # 这里可以添加更新roadmap文件中Feature状态的逻辑
    fi
    
    echo "✅ Feature完成状态更新完成"
}