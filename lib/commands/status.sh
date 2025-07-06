#!/bin/bash
# GPF Commands - Status Command
# 智能状态显示命令 - 其他命令的基础支撑

set -euo pipefail

# 1. 导入依赖Modules（严格遵循四层架构）
# 注意：只调用Modules层，绝不跨层调用Composite或Atomic层

# 临时获取脚本目录以加载modules（之后通过modules获取项目根目录）
TEMP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_PROJECT_ROOT="$(cd "$TEMP_SCRIPT_DIR/../.." && pwd)"

# 加载environment module获取正确的项目根目录
source "$TEMP_PROJECT_ROOT/lib/core/modules/environment-module.sh"

# 通过modules层获取项目根目录（遵循四层架构）
PROJECT_ROOT=$(environment_get_project_root) || {
    echo "❌ 错误：无法通过modules层获取项目根目录" >&2
    exit 1
}

# 加载其他必需的modules
source "$PROJECT_ROOT/lib/core/modules/validation-module.sh"

# 尝试加载status module，如果不存在则会在开发过程中回到Epic1补充
if [[ -f "$PROJECT_ROOT/lib/core/modules/status-module.sh" ]]; then
    source "$PROJECT_ROOT/lib/core/modules/status-module.sh"
else
    echo "⚠️  模块缺失: status-module.sh"
    echo "📋 需要回到Epic1补充此模块"
fi

# 全局变量存储命令参数
COMMAND_SCOPE=""      # epic名称或feature名称
COMMAND_TARGET=""     # 具体目标
SHOW_DETAILED=false   # 是否显示详细信息
OUTPUT_FORMAT="human" # 输出格式: human|json

# 2. 命令参数解析
parse_command_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --detailed|-d)
                SHOW_DETAILED=true
                shift
                ;;
            --json|-j)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$COMMAND_SCOPE" ]]; then
                    COMMAND_SCOPE="$1"
                elif [[ -z "$COMMAND_TARGET" ]]; then
                    COMMAND_TARGET="$1"
                else
                    echo "❌ 错误：未知参数 $1" >&2
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
GPF Status - 智能状态显示

用法:
  gpf status [epic] [feature] [options]

参数:
  epic        显示指定Epic的状态
  feature     显示指定Feature的状态

选项:
  -d, --detailed    显示详细状态信息
  -j, --json        以JSON格式输出
  -h, --help        显示此帮助信息

示例:
  gpf status                    # 显示当前环境状态
  gpf status auth               # 显示auth epic状态
  gpf status auth login         # 显示auth epic下login feature状态
  gpf status --detailed         # 显示详细状态
  gpf status --json             # JSON格式输出

功能:
  - 智能环境检测和状态显示
  - 为pr、clean、sync命令提供状态检查支撑
  - 根据当前环境自动确定显示范围
EOF
}

# 3. 环境验证
validate_command_environment() {
    echo "🔍 验证status命令执行环境..."
    
    # 检查是否在Git项目中
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 错误：当前不在Git项目中" >&2
        return 1
    fi
    
    # status命令可以在任何环境执行，无特殊限制
    echo "✅ 环境验证通过"
    return 0
}

# 4. 核心业务逻辑（只调用Modules方法）
execute_command_logic() {
    echo "📊 收集状态信息..."
    
    # 4.1 环境检测 (调用environment module)
    local current_env_info
    if command -v environment_module_get_complete_info >/dev/null 2>&1; then
        current_env_info=$(environment_module_get_complete_info) || {
            echo "❌ 环境检测失败" >&2
            return 1
        }
    else
        echo "⚠️  功能缺失: environment_module_get_complete_info"
        echo "📋 需要回到Epic1的environment-module.sh中补充此方法"
        # 临时简单实现以继续开发
        current_env_info='{"environment_type": "unknown", "current_path": "'$(pwd)'"}'
    fi
    
    # 4.2 确定显示范围
    local display_scope
    display_scope=$(determine_display_scope "$current_env_info")
    
    # 4.3 收集状态信息 (调用status module)  
    local status_info
    if command -v status_module_get_complete_status >/dev/null 2>&1; then
        status_info=$(status_module_get_complete_status "$display_scope") || {
            echo "❌ 状态收集失败" >&2
            return 1
        }
    else
        echo "⚠️  功能缺失: status_module_get_complete_status"
        echo "📋 需要回到Epic1的status-module.sh中补充此方法"
        # 临时简单实现
        status_info='{"status": "unknown", "message": "status module not implemented"}'
    fi
    
    # 4.4 格式化输出
    format_and_display_status "$current_env_info" "$status_info"
    
    return 0
}

# 确定显示范围
determine_display_scope() {
    local env_info="$1"
    
    # 根据参数和当前环境确定显示范围
    if [[ -n "$COMMAND_SCOPE" ]]; then
        if [[ -n "$COMMAND_TARGET" ]]; then
            echo "feature:$COMMAND_SCOPE:$COMMAND_TARGET"
        else
            echo "epic:$COMMAND_SCOPE"
        fi
    else
        # 根据当前环境自动确定
        local env_type
        env_type=$(echo "$env_info" | grep -o '"environment_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
        
        case "$env_type" in
            "root")
                echo "all_epics"
                ;;
            "epic")
                echo "current_epic"
                ;;
            "feature")
                echo "current_feature"
                ;;
            *)
                echo "current_context"
                ;;
        esac
    fi
}

# 格式化和显示状态
format_and_display_status() {
    local env_info="$1"
    local status_info="$2"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        # JSON格式输出
        cat << EOF
{
    "environment": $env_info,
    "status": $status_info,
    "command_options": {
        "scope": "$COMMAND_SCOPE",
        "target": "$COMMAND_TARGET", 
        "detailed": $SHOW_DETAILED,
        "format": "$OUTPUT_FORMAT"
    }
}
EOF
    else
        # 用户友好格式
        echo "🎯 GPF Status Report"
        echo "===================="
        
        # 显示当前环境
        local env_type
        env_type=$(echo "$env_info" | grep -o '"environment_type": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
        echo "📍 当前环境: $env_type"
        
        # 显示状态摘要
        echo ""
        echo "📊 状态摘要:"
        echo "$status_info" | grep -o '"message": "[^"]*"' | cut -d'"' -f4 || echo "状态信息获取中..."
        
        if [[ "$SHOW_DETAILED" == "true" ]]; then
            echo ""
            echo "🔍 详细信息:"
            echo "环境信息: $env_info"
            echo "状态信息: $status_info"
        fi
        
        echo ""
        echo "✅ Status命令执行完成"
    fi
}

# 5. 主入口
main() {
    echo "🚀 GPF Status - 智能状态显示"
    echo ""
    
    # 解析参数
    parse_command_arguments "$@"
    
    # 验证环境
    validate_command_environment || exit 1
    
    # 执行核心逻辑
    execute_command_logic || exit 1
    
    echo ""
    echo "💡 提示: 使用 'gpf status --help' 查看更多选项"
}

# 执行主函数（当直接运行此脚本时）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi