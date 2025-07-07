#!/bin/bash
# GPF Commands - Status Command
# 智能状态显示命令 - 四阶段架构实现

set -euo pipefail

# ===================================================================
# 模块依赖 - 严格遵循四层架构，只调用Modules层
# ===================================================================

# 获取脚本目录以加载modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 避免在测试模式下加载模块（防止冲突）
if [[ "${GPF_TEST_MODE:-}" != "true" ]]; then
    # 使用相对路径加载必需的modules
    source "$(dirname "${BASH_SOURCE[0]}")/../core/modules/environment-module.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/../core/modules/status-module.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/../core/modules/paths-module.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/../core/modules/worktree-module.sh"
fi

# ===================================================================
# 第一阶段：参数处理和验证
# ===================================================================

status_command_process_parameters() {
    local target_input="$1"
    local output_format="$2"
    local status_purpose="$3"
    local options_json="$4"
    
    # 验证输出格式
    case "$output_format" in
        "human"|"json"|"compact") ;;
        *) 
            echo "❌ 错误：不支持的输出格式: $output_format" >&2
            return 1
            ;;
    esac
    
    # 验证状态目的
    case "$status_purpose" in
        "status"|"pr"|"clean"|"sync"|"start") ;;
        *)
            echo "❌ 错误：不支持的状态目的: $status_purpose" >&2
            return 1
            ;;
    esac
    
    # 处理目标输入（支持用户友好输入）
    local processed_target=""
    local target_branch=""
    
    if [[ -n "$target_input" ]]; then
        # 使用paths模块智能解析用户输入
        if command -v paths_module_smart_branch_resolve >/dev/null 2>&1; then
            target_branch=$(paths_module_smart_branch_resolve "$target_input")
            processed_target="$target_branch"
        else
            # 简单处理：如果没有前缀则添加epic-前缀
            if [[ "$target_input" =~ ^epic- ]]; then
                processed_target="$target_input"
                target_branch="$target_input"
            else
                processed_target="epic-$target_input-e"
                target_branch="epic-$target_input-e"
            fi
        fi
        
        # 验证用户输入
        if command -v paths_module_validate_user_input >/dev/null 2>&1; then
            if ! paths_module_validate_user_input "$target_input"; then
                echo "❌ 错误：无效的目标输入: $target_input" >&2
                return 1
            fi
        fi
    fi
    
    # 返回处理结果JSON
    cat <<EOF
{
    "target_input": "$target_input",
    "processed_target": "$processed_target", 
    "target_branch": "$target_branch",
    "output_format": "$output_format",
    "status_purpose": "$status_purpose",
    "options": $options_json
}
EOF
}

# ===================================================================
# 第二阶段：环境检测和准备
# ===================================================================

status_command_detect_and_prepare_environment() {
    local processed_params="$1"
    
    # 获取当前环境上下文
    local current_context
    if command -v environment_module_get_current_context >/dev/null 2>&1; then
        current_context=$(environment_module_get_current_context)
    else
        # 简单环境检测
        current_context=$(cat <<EOF
{
    "type": "root",
    "current_path": "$(pwd)",
    "project_root": "$PROJECT_ROOT",
    "epic_name": "",
    "feature_name": ""
}
EOF
)
    fi
    
    # 确定目标环境
    local target_branch
    target_branch=$(echo "$processed_params" | jq -r '.target_branch // empty')
    
    local target_context
    local requires_switching="false"
    
    if [[ -n "$target_branch" ]]; then
        # 有指定目标，需要检查是否需要切换
        local current_branch
        current_branch=$(echo "$current_context" | jq -r '.current_branch // ""')
        
        if [[ "$current_branch" != "$target_branch" ]]; then
            requires_switching="true"
        fi
        
        # 构建目标上下文
        if [[ "$target_branch" =~ -ef$ ]]; then
            target_context=$(echo '{"type": "feature", "target_branch": "'$target_branch'"}')
        elif [[ "$target_branch" =~ -e$ ]]; then
            target_context=$(echo '{"type": "epic", "target_branch": "'$target_branch'"}')
        else
            target_context=$(echo '{"type": "unknown", "target_branch": "'$target_branch'"}')
        fi
    else
        # 无指定目标，使用当前环境
        target_context="$current_context"
    fi
    
    # 获取状态目的
    local status_purpose
    status_purpose=$(echo "$processed_params" | jq -r '.status_purpose')
    
    # 返回环境信息JSON
    cat <<EOF
{
    "current_context": $current_context,
    "target_context": $target_context,
    "requires_switching": $requires_switching,
    "status_purpose": "$status_purpose"
}
EOF
}

# ===================================================================
# 第三阶段：状态收集和集成
# ===================================================================

status_command_collect_status_data() {
    local environment_context="$1"
    local processed_params="$2"
    
    # 确定要检查的分支
    local branch_to_check
    local target_branch_for_status
    
    local requires_switching
    requires_switching=$(echo "$environment_context" | jq -r '.requires_switching')
    
    if [[ "$requires_switching" == "true" ]]; then
        # 检查目标分支
        branch_to_check=$(echo "$environment_context" | jq -r '.target_context.target_branch')
        target_branch_for_status="develop"
    else
        # 检查当前分支
        local current_type
        current_type=$(echo "$environment_context" | jq -r '.current_context.type')
        
        case "$current_type" in
            "feature")
                # Feature分支，目标是其Epic分支
                branch_to_check=$(echo "$environment_context" | jq -r '.current_context.current_branch // ""')
                target_branch_for_status=$(echo "$environment_context" | jq -r '.current_context.epic_branch // "develop"')
                ;;
            "epic")
                # Epic分支，目标是develop
                branch_to_check=$(echo "$environment_context" | jq -r '.current_context.current_branch // ""')
                target_branch_for_status="develop"
                ;;
            *)
                # 根环境或其他，检查develop
                branch_to_check="develop"
                target_branch_for_status="main"
                ;;
        esac
    fi
    
    # 获取状态目的
    local status_purpose
    status_purpose=$(echo "$processed_params" | jq -r '.status_purpose')
    
    # 调用status模块获取完整状态
    local complete_status
    if command -v status_module_get_complete_status >/dev/null 2>&1; then
        complete_status=$(status_module_get_complete_status "$branch_to_check" "$target_branch_for_status" "$status_purpose" 2>&1)
        
        # 验证返回的是否为有效JSON
        if ! echo "$complete_status" | jq . >/dev/null 2>&1; then
            echo "$complete_status" >&2
            return 1
        fi
    else
        # 简单状态信息
        complete_status=$(cat <<EOF
{
    "purpose": "$status_purpose",
    "branch_name": "$branch_to_check",
    "target_branch": "$target_branch_for_status",
    "pr_ready": true,
    "start_ready": true,
    "sync_ready": false,
    "safety_level": "safe",
    "blocking_issues": [],
    "warnings": [],
    "base_status": {
        "working_tree_clean": true,
        "staging_area_clean": true,
        "branch_pushed": false,
        "has_merge_conflicts": false,
        "branch_exists": true
    }
}
EOF
)
    fi
    
    # 获取环境信息
    local environment_info
    environment_info=$(echo "$environment_context" | jq '.current_context')
    
    # 返回状态数据JSON
    cat <<EOF
{
    "branch_to_check": "$branch_to_check",
    "target_branch_for_status": "$target_branch_for_status",
    "status_purpose": "$status_purpose",
    "complete_status": $complete_status,
    "environment_info": $environment_info
}
EOF
}

# ===================================================================
# 第四阶段：输出格式化和显示
# ===================================================================

status_command_format_and_display() {
    local status_data="$1"
    local processed_params="$2"
    
    local output_format
    output_format=$(echo "$processed_params" | jq -r '.output_format')
    
    case "$output_format" in
        "json")
            # JSON格式输出
            cat <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "command": "status",
    "version": "1.0.0",
    "data": $status_data,
    "parameters": $processed_params
}
EOF
            ;;
        "compact")
            # 紧凑格式输出
            local branch_name
            local working_clean
            local staging_clean
            local conflicts
            
            branch_name=$(echo "$status_data" | jq -r '.branch_to_check')
            working_clean=$(echo "$status_data" | jq -r '.complete_status.base_status.working_tree_clean // false')
            staging_clean=$(echo "$status_data" | jq -r '.complete_status.base_status.staging_area_clean // false')
            conflicts=$(echo "$status_data" | jq -r '.complete_status.base_status.has_merge_conflicts // false')
            
            local status_indicator="🟢"
            if [[ "$working_clean" != "true" || "$staging_clean" != "true" ]]; then
                status_indicator="🟡"
            fi
            if [[ "$conflicts" == "true" ]]; then
                status_indicator="🔴"
            fi
            
            echo "$status_indicator $branch_name"
            ;;
        *)
            # 人类可读格式（默认）
            local branch_name
            local status_purpose
            local environment_type
            
            branch_name=$(echo "$status_data" | jq -r '.branch_to_check')
            status_purpose=$(echo "$status_data" | jq -r '.status_purpose')
            environment_type=$(echo "$status_data" | jq -r '.environment_info.type // "unknown"')
            
            echo "🎯 GPF 状态报告"
            echo "==============="
            echo "📍 当前Epic环境类型: $environment_type"
            echo "🌿 Git分支: $branch_name"
            echo "🎯 目的: $status_purpose"
            echo ""
            
            # 显示基础状态
            local working_clean
            local staging_clean
            local branch_pushed
            local conflicts
            
            working_clean=$(echo "$status_data" | jq -r '.complete_status.base_status.working_tree_clean // false')
            staging_clean=$(echo "$status_data" | jq -r '.complete_status.base_status.staging_area_clean // false')
            branch_pushed=$(echo "$status_data" | jq -r '.complete_status.base_status.branch_pushed // false')
            conflicts=$(echo "$status_data" | jq -r '.complete_status.base_status.has_merge_conflicts // false')
            
            echo "📊 本地Git状态:"
            echo "   Git工作区干净: $(status_command_format_boolean "$working_clean")"
            echo "   Git暂存区干净: $(status_command_format_boolean "$staging_clean")"
            echo "   Git分支已推送: $(status_command_format_boolean "$branch_pushed")"
            echo "   Git合并是否有冲突: $(status_command_format_conflict_boolean "$conflicts")"
            
                        # 显示GitHub/PR状态
            local gh_available
            local pr_exists
            local pr_number
            local pr_state
            
            gh_available=$(echo "$status_data" | jq -r '.complete_status.github_status.gh_available // false')
            pr_exists=$(echo "$status_data" | jq -r '.complete_status.github_status.pr_exists // false')
            pr_number=$(echo "$status_data" | jq -r '.complete_status.github_status.pr_number // ""')
            pr_state=$(echo "$status_data" | jq -r '.complete_status.github_status.pr_state // ""')
            
            echo ""
            echo "🔗 GitHub状态:"
            echo "   GitHub CLI可用: $(status_command_format_boolean "$gh_available")"
            if [[ "$gh_available" == "true" ]]; then
                echo "   PR存在: $(status_command_format_boolean "$pr_exists")"
                if [[ "$pr_exists" == "true" ]]; then
                    echo "   PR编号: #$pr_number"
                    echo "   PR状态: $pr_state"
                fi
            else
                echo "   💡 提示: 在终端运行 'gh auth login' 命令启用GitHub功能"
            fi
            
            echo ""
            echo "✅ 状态检查完成"
            ;;
    esac
}

# ===================================================================
# 辅助函数
# ===================================================================

status_command_format_boolean() {
    local value="$1"
    if [[ "$value" == "true" ]]; then
        echo "✅ 是"
    else
        echo "❌ 否"
    fi
}

status_command_format_conflict_boolean() {
    local value="$1"
    if [[ "$value" == "true" ]]; then
        echo "🔥 存在"
    else
        echo "✅ 无"
    fi
}

status_command_show_help() {
    cat <<EOF
GPF Status Command - 查看分支和环境状态

用法:
    gpf status [TARGET] [OPTIONS]

参数:
    TARGET          可选的目标分支名称（支持简化输入）
                   例如: auth, epic-auth-e, feature-login

选项:
    --json          JSON格式输出
    --compact       紧凑格式输出
    --pr            检查PR准备状态
    --clean         检查清理安全性
    --sync          检查同步状态
    --start         检查开始操作状态
    --format FORMAT 输出格式 (human|json|compact，默认: human)
    --purpose PURPOSE 状态目的 (status|pr|clean|sync|start，默认: status)
    --help          显示此帮助信息

示例:
    gpf status                    # 检查当前环境状态
    gpf status auth               # 检查auth相关分支状态
    gpf status --pr               # 检查PR准备状态
    gpf status auth --pr          # 检查auth分支的PR状态
    gpf status --clean            # 检查清理安全性
    gpf status --json             # JSON格式输出
    gpf status auth --pr --json   # 检查auth分支PR状态，JSON输出

功能:
    - 智能环境检测和状态显示
    - 为pr、clean、sync命令提供状态检查支撑
    - 根据当前环境自动确定显示范围
EOF
}

# ===================================================================
# 主函数和命令入口
# ===================================================================

status_command_main() {
    local target_input="${1:-}"
    local output_format="${2:-human}"
    local status_purpose="${3:-status}"
    local options_json="$4"
    
    # 安全处理JSON选项
    if [[ -z "$options_json" ]]; then
        options_json="{}"
    fi
    
    # 第一阶段：参数处理
    local processed_params
    processed_params=$(status_command_process_parameters "$target_input" "$output_format" "$status_purpose" "$options_json") || return 1
    
    # 第二阶段：环境检测
    local environment_context
    environment_context=$(status_command_detect_and_prepare_environment "$processed_params") || return 1
    
    # 第三阶段：状态收集
    local status_data
    status_data=$(status_command_collect_status_data "$environment_context" "$processed_params") || return 1
    
    # 第四阶段：格式化显示
    status_command_format_and_display "$status_data" "$processed_params"
}

# 传统命令行接口（向后兼容）
main() {
    local target=""
    local output_format="human"
    local status_purpose="status"
    local show_help=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --format=*)
                output_format="${1#*=}"
                shift
                ;;
            --json)
                output_format="json"
                shift
                ;;
            --compact)
                output_format="compact"
                shift
                ;;
            --purpose=*)
                status_purpose="${1#*=}"
                shift
                ;;
            --pr)
                status_purpose="pr"
                shift
                ;;
            --clean)
                status_purpose="clean"
                shift
                ;;
            --sync)
                status_purpose="sync"
                shift
                ;;
            --start)
                status_purpose="start"
                shift
                ;;
            --help|-h)
                show_help=true
                shift
                ;;
            --*)
                echo "❌ 错误：未知选项 $1" >&2
                status_command_show_help
                return 1
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                else
                    echo "❌ 错误：过多参数 $1" >&2
                    status_command_show_help
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ "$show_help" == "true" ]]; then
        status_command_show_help
        return 0
    fi
    
    # 调用主函数
    status_command_main "$target" "$output_format" "$status_purpose" "{}"
}

# 执行主函数（当直接运行此脚本时）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi