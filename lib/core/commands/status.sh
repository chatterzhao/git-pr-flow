#!/bin/bash
# GPF Commands层 - Status命令实现
# 作为第一个Commands层实现，展示薄层编排模式和通用接口设计

set -euo pipefail

# 获取脚本所在目录 - 使用相对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 计算项目根目录 - 从commands目录向上3级到项目根
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 避免变量冲突，在测试模式下跳过模块加载
if [[ "${GPF_TEST_MODE:-}" != "true" ]]; then
    # 使用相对路径加载依赖 - 遵循相对路径原则
    source "$SCRIPT_DIR/../common.sh"
    source "$SCRIPT_DIR/../modules/environment-module.sh"
    source "$SCRIPT_DIR/../modules/status-module.sh"
    source "$SCRIPT_DIR/../modules/paths-module.sh" 
    source "$SCRIPT_DIR/../modules/worktree-module.sh"
fi

# ==============================================================================
# Commands层 - Status命令入口点
# ==============================================================================

# Status命令主入口（Commands层标准接口）
status_command_main() {
    local target_input="${1:-}"         # 可选的目标分支
    local output_format="${2:-human}"   # human/json/compact
    local status_purpose="${3:-status}" # status/pr/clean/sync/start
    local options="${4:-}"              # JSON格式的额外选项
    
    # 第一阶段：参数处理和验证
    local processed_params
    processed_params=$(status_command_process_parameters "$target_input" "$output_format" "$status_purpose" "$options") || return 1
    
    # 第二阶段：智能环境检测和切换
    local environment_context
    environment_context=$(status_command_detect_and_prepare_environment "$processed_params") || return 1
    
    # 第三阶段：状态检查和收集
    local status_data
    status_data=$(status_command_collect_status_data "$environment_context" "$processed_params") || return 1
    
    # 第四阶段：输出格式化和显示
    status_command_format_and_display "$status_data" "$processed_params"
}

# ==============================================================================
# 第一阶段：参数处理（Commands层职责）
# ==============================================================================

# 处理和验证命令参数
status_command_process_parameters() {
    local target_input="$1"
    local output_format="$2"
    local status_purpose="$3"
    local options="$4"
    
    # 解析和验证输出格式
    case "$output_format" in
        "human"|"json"|"compact")
            # 有效格式
            ;;
        *)
            echo "❌ 错误：不支持的输出格式: $output_format" >&2
            echo "支持的格式: human, json, compact" >&2
            return 1
            ;;
    esac
    
    # 验证状态目的
    case "$status_purpose" in
        "status"|"pr"|"clean"|"sync"|"start")
            # 有效目的
            ;;
        *)
            echo "❌ 错误：不支持的状态目的: $status_purpose" >&2
            echo "支持的目的: status, pr, clean, sync, start" >&2
            return 1
            ;;
    esac
    
    # 处理目标输入（如果提供）
    local processed_target=""
    local target_branch=""
    
    if [[ -n "$target_input" ]]; then
        # 验证用户输入格式
        if ! paths_module_validate_user_input "$target_input"; then
            echo "❌ 错误：目标输入格式不正确" >&2
            return 1
        fi
        
        # 转换为标准分支名
        target_branch=$(paths_module_smart_branch_resolve "$target_input") || {
            echo "❌ 错误：无法解析目标分支" >&2
            return 1
        }
        
        processed_target="$target_branch"
    fi
    
    # 解析额外选项
    local parsed_options="{}"
    if [[ -n "$options" ]]; then
        if ! echo "$options" | jq . >/dev/null 2>&1; then
            echo "❌ 错误：选项必须是有效的JSON格式" >&2
            return 1
        fi
        parsed_options="$options"
    fi
    
    # 返回处理后的参数
    cat <<EOF
{
    "target_input": "$target_input",
    "processed_target": "$processed_target",
    "target_branch": "$target_branch",
    "output_format": "$output_format",
    "status_purpose": "$status_purpose",
    "options": $parsed_options
}
EOF
}

# ==============================================================================
# 第二阶段：环境检测（Commands层编排，调用Modules层）
# ==============================================================================

# 检测和准备环境
status_command_detect_and_prepare_environment() {
    local processed_params="$1"
    
    local target_branch=$(echo "$processed_params" | jq -r '.target_branch')
    local status_purpose=$(echo "$processed_params" | jq -r '.status_purpose')
    
    # 获取当前环境上下文
    local current_context
    current_context=$(environment_module_get_current_context) || {
        echo "❌ 错误：无法获取环境上下文" >&2
        return 1
    }
    
    # 确定目标环境
    local target_context="$current_context"
    
    if [[ -n "$target_branch" ]]; then
        # 需要检查目标分支环境
        local target_worktree_path="$PROJECT_ROOT/.worktrees/$target_branch"
        
        if [[ -d "$target_worktree_path" ]]; then
            # 目标工作树存在，获取其上下文
            target_context=$(cat <<EOF
{
    "type": "$(echo "$target_branch" | grep -q "\\-e\\-.*\\-ef$" && echo "feature" || echo "epic")",
    "current_path": "$target_worktree_path",
    "project_root": "$PROJECT_ROOT",
    "target_branch": "$target_branch"
}
EOF
            )
        else
            # 目标工作树不存在
            target_context=$(cat <<EOF
{
    "type": "nonexistent",
    "current_path": "$(pwd)",
    "project_root": "$PROJECT_ROOT",
    "target_branch": "$target_branch",
    "error": "target worktree does not exist"
}
EOF
            )
        fi
    fi
    
    # 合并环境信息
    cat <<EOF
{
    "current_context": $current_context,
    "target_context": $target_context,
    "requires_switching": $(if [[ -n "$target_branch" ]]; then echo "true"; else echo "false"; fi),
    "status_purpose": "$status_purpose"
}
EOF
}

# ==============================================================================
# 第三阶段：状态收集（Commands层编排，调用Modules层）
# ==============================================================================

# 收集状态数据
status_command_collect_status_data() {
    local environment_context="$1"
    local processed_params="$2"
    
    local current_context=$(echo "$environment_context" | jq -r '.current_context')
    local target_context=$(echo "$environment_context" | jq -r '.target_context')
    local status_purpose=$(echo "$processed_params" | jq -r '.status_purpose')
    local target_branch=$(echo "$processed_params" | jq -r '.target_branch')
    
    # 确定要检查的分支
    local branch_to_check=""
    local target_branch_for_status=""
    
    if [[ -n "$target_branch" && "$target_branch" != "null" ]]; then
        branch_to_check="$target_branch"
        # 根据分支类型确定目标分支
        if [[ "$target_branch" =~ ^epic-.*-e-.*-ef$ ]]; then
            # Feature分支，目标是对应的Epic分支
            local epic_part="${target_branch%-e-*-ef}"
            target_branch_for_status="$epic_part-e"
        else
            # Epic分支，目标是develop
            target_branch_for_status="develop"
        fi
    else
        # 使用当前环境
        local current_type=$(echo "$current_context" | jq -r '.type')
        
        case "$current_type" in
            "epic"|"feature")
                local current_branch=$(echo "$current_context" | jq -r '.current_branch // ""')
                if [[ -n "$current_branch" ]]; then
                    branch_to_check="$current_branch"
                    # 根据当前分支类型确定目标分支
                    if [[ "$current_branch" =~ ^epic-.*-e-.*-ef$ ]]; then
                        local epic_part="${current_branch%-e-*-ef}"
                        target_branch_for_status="$epic_part-e"
                    else
                        target_branch_for_status="develop"
                    fi
                else
                    echo "❌ 错误：无法确定当前分支" >&2
                    return 1
                fi
                ;;
            "root")
                # 在根目录，检查当前分支
                branch_to_check=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "develop")
                target_branch_for_status="develop"
                ;;
            *)
                echo "❌ 错误：无法在当前环境中执行状态检查" >&2
                return 1
                ;;
        esac
    fi
    
    # 调用Modules层获取完整状态
    local complete_status
    complete_status=$(status_module_get_complete_status "$branch_to_check" "$target_branch_for_status" "$status_purpose") || {
        echo "❌ 错误：状态检查失败" >&2
        return 1
    }
    
    # 获取环境补充信息
    local environment_info
    environment_info=$(status_command_get_environment_supplement "$environment_context") || environment_info="{}"
    
    # 合并所有状态数据
    cat <<EOF
{
    "branch_to_check": "$branch_to_check",
    "target_branch_for_status": "$target_branch_for_status",
    "status_purpose": "$status_purpose",
    "complete_status": $complete_status,
    "environment_info": $environment_info,
    "environment_context": $environment_context
}
EOF
}

# 获取环境补充信息
status_command_get_environment_supplement() {
    local environment_context="$1"
    
    local current_context=$(echo "$environment_context" | jq -r '.current_context')
    local current_type=$(echo "$current_context" | jq -r '.type')
    
    # 根据环境类型获取补充信息
    case "$current_type" in
        "epic"|"feature")
            # 获取工作树快速状态
            local quick_status
            quick_status=$(worktree_module_quick_status) || quick_status="{}"
            
            cat <<EOF
{
    "worktree_status": $quick_status,
    "environment_type": "$current_type"
}
EOF
            ;;
        "root")
            cat <<EOF
{
    "environment_type": "root",
    "note": "在项目根目录中"
}
EOF
            ;;
        *)
            cat <<EOF
{
    "environment_type": "unknown",
    "note": "未知环境类型"
}
EOF
            ;;
    esac
}

# ==============================================================================
# 第四阶段：输出格式化（Commands层职责）
# ==============================================================================

# 格式化和显示状态
status_command_format_and_display() {
    local status_data="$1"
    local processed_params="$2"
    
    local output_format=$(echo "$processed_params" | jq -r '.output_format')
    local complete_status=$(echo "$status_data" | jq -r '.complete_status')
    local status_purpose=$(echo "$status_data" | jq -r '.status_purpose')
    local branch_to_check=$(echo "$status_data" | jq -r '.branch_to_check')
    
    case "$output_format" in
        "json")
            # JSON格式：直接输出原始数据
            echo "$status_data" | jq .
            ;;
        "compact")
            # 紧凑格式：一行摘要
            status_command_format_compact "$status_data"
            ;;
        "human")
            # 人类可读格式：详细格式化
            status_command_format_human "$status_data"
            ;;
    esac
}

# 紧凑格式输出
status_command_format_compact() {
    local status_data="$1"
    
    local complete_status=$(echo "$status_data" | jq -r '.complete_status')
    local branch_to_check=$(echo "$status_data" | jq -r '.branch_to_check')
    local status_purpose=$(echo "$status_data" | jq -r '.status_purpose')
    
    # 提取关键状态指标
    local base_status=$(echo "$complete_status" | jq -r '.base_status')
    local working_clean=$(echo "$base_status" | jq -r '.working_tree_clean')
    local staging_clean=$(echo "$base_status" | jq -r '.staging_area_clean')
    local has_conflicts=$(echo "$base_status" | jq -r '.has_merge_conflicts // false')
    
    # 构建状态指示器
    local status_indicators=""
    [[ "$working_clean" == "true" ]] && status_indicators+="W✓" || status_indicators+="W✗"
    [[ "$staging_clean" == "true" ]] && status_indicators+=" S✓" || status_indicators+=" S✗"
    [[ "$has_conflicts" == "true" ]] && status_indicators+=" 🔥" || status_indicators+=""
    
    echo "$branch_to_check [$status_purpose] $status_indicators"
}

# 人类可读格式输出
status_command_format_human() {
    local status_data="$1"
    
    local complete_status=$(echo "$status_data" | jq -r '.complete_status')
    local branch_to_check=$(echo "$status_data" | jq -r '.branch_to_check')
    local target_branch=$(echo "$status_data" | jq -r '.target_branch_for_status')
    local status_purpose=$(echo "$status_data" | jq -r '.status_purpose')
    local environment_info=$(echo "$status_data" | jq -r '.environment_info')
    
    echo "🔍 Status Report for $branch_to_check"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 显示基础状态
    local base_status=$(echo "$complete_status" | jq -r '.base_status')
    echo "📋 Basic Status:"
    echo "   Working Tree: $(status_command_format_boolean "$(echo "$base_status" | jq -r '.working_tree_clean')")"
    echo "   Staging Area: $(status_command_format_boolean "$(echo "$base_status" | jq -r '.staging_area_clean')")"
    echo "   Branch Pushed: $(status_command_format_boolean "$(echo "$base_status" | jq -r '.branch_pushed')")"
    
    # 检查冲突
    local has_conflicts=$(echo "$base_status" | jq -r '.has_merge_conflicts // false')
    if [[ "$has_conflicts" == "true" ]]; then
        echo "   🔥 CONFLICTS: Yes"
    fi
    
    # 显示目的特定状态
    case "$status_purpose" in
        "pr")
            local pr_ready=$(echo "$complete_status" | jq -r '.pr_ready')
            echo ""
            echo "🎯 PR Readiness: $(status_command_format_boolean "$pr_ready")"
            local blocking_issues=$(echo "$complete_status" | jq -r '.blocking_issues[]' 2>/dev/null || echo "")
            if [[ -n "$blocking_issues" ]]; then
                echo "   ⚠️  Blocking Issues:"
                echo "$blocking_issues" | while read -r issue; do
                    [[ -n "$issue" ]] && echo "      - $issue"
                done
            fi
            ;;
        "start")
            local start_ready=$(echo "$complete_status" | jq -r '.start_ready')
            echo ""
            echo "🚀 Start Readiness: $(status_command_format_boolean "$start_ready")"
            local blocking_issues=$(echo "$complete_status" | jq -r '.blocking_issues[]' 2>/dev/null || echo "")
            local warnings=$(echo "$complete_status" | jq -r '.warnings[]' 2>/dev/null || echo "")
            if [[ -n "$blocking_issues" ]]; then
                echo "   🚫 Blocking Issues:"
                echo "$blocking_issues" | while read -r issue; do
                    [[ -n "$issue" ]] && echo "      - $issue"
                done
            fi
            if [[ -n "$warnings" ]]; then
                echo "   ⚠️  Warnings:"
                echo "$warnings" | while read -r warning; do
                    [[ -n "$warning" ]] && echo "      - $warning"
                done
            fi
            ;;
        "clean")
            local safety_level=$(echo "$complete_status" | jq -r '.safety_level')
            local safety_color=$(echo "$complete_status" | jq -r '.safety_color')
            echo ""
            echo "🧹 Clean Safety: $safety_color $safety_level"
            ;;
        "sync")
            local sync_ready=$(echo "$complete_status" | jq -r '.sync_ready')
            local needs_sync=$(echo "$complete_status" | jq -r '.needs_sync // false')
            echo ""
            echo "🔄 Sync Status: Ready=$(status_command_format_boolean "$sync_ready"), Needed=$(status_command_format_boolean "$needs_sync")"
            ;;
    esac
    
    # 显示环境信息
    local env_type=$(echo "$environment_info" | jq -r '.environment_type')
    echo ""
    echo "🌍 Environment: $env_type"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 格式化布尔值显示
status_command_format_boolean() {
    local value="$1"
    case "$value" in
        "true")  echo "✅ Yes" ;;
        "false") echo "❌ No" ;;
        *)       echo "❓ Unknown" ;;
    esac
}

# ==============================================================================
# Commands层辅助功能
# ==============================================================================

# 显示使用帮助
status_command_show_help() {
    cat <<EOF
GPF Status Command - 查看分支和环境状态

用法:
    gpf status [TARGET] [OPTIONS]

参数:
    TARGET          可选的目标分支名称（支持简化输入）
                   例如: auth, epic-auth-e, feature-login

选项:
    --format FORMAT 输出格式 (human|json|compact，默认: human)
    --purpose PURPOSE 状态目的 (status|pr|clean|sync|start，默认: status)
    --help          显示此帮助信息

示例:
    gpf status                    # 检查当前环境状态
    gpf status auth               # 检查auth相关分支状态
    gpf status --format=json     # JSON格式输出
    gpf status --purpose=pr      # 检查PR准备状态

EOF
}

# ==============================================================================
# 模块导出 - Commands层标准接口
# ==============================================================================

# 如果直接执行此脚本，运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 解析命令行参数
    target_input=""
    output_format="human"
    status_purpose="status"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --format=*)
                output_format="${1#*=}"
                shift
                ;;
            --purpose=*)
                status_purpose="${1#*=}"
                shift
                ;;
            --help|-h)
                status_command_show_help
                exit 0
                ;;
            -*)
                echo "❌ 错误：未知选项 $1" >&2
                status_command_show_help
                exit 1
                ;;
            *)
                if [[ -z "$target_input" ]]; then
                    target_input="$1"
                else
                    echo "❌ 错误：过多的参数" >&2
                    status_command_show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 执行status命令
    status_command_main "$target_input" "$output_format" "$status_purpose"
fi