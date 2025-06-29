#!/usr/bin/env bash

# Git PR Flow - 环境检测工具
# 检测非交互式环境，为自动化和CI/CD场景提供支持

# 避免重复加载
if [[ -n "${GPF_ENVIRONMENT_LOADED:-}" ]]; then
    return 0
fi
GPF_ENVIRONMENT_LOADED=1

# ===================================================== 
# 非交互式环境检测
# =====================================================

# 检测是否在非交互式环境中
is_non_interactive() {
    # 检查多个指标来确定是否为非交互式环境
    
    # 1. 检查标准输入是否是终端
    if [[ ! -t 0 ]]; then
        return 0
    fi
    
    # 2. 检查是否设置了明确的非交互式标志
    if [[ "${GPF_NON_INTERACTIVE:-}" == "true" ]]; then
        return 0
    fi
    
    # 3. 检查CI环境变量
    if [[ -n "${CI:-}" || -n "${CONTINUOUS_INTEGRATION:-}" ]]; then
        return 0
    fi
    
    # 4. 检查常见CI平台环境变量
    if [[ -n "${GITHUB_ACTIONS:-}" || 
          -n "${GITLAB_CI:-}" || 
          -n "${JENKINS_URL:-}" || 
          -n "${BUILDKITE:-}" || 
          -n "${CIRCLECI:-}" || 
          -n "${TRAVIS:-}" || 
          -n "${APPVEYOR:-}" ]]; then
        return 0
    fi
    
    # 5. 检查TERM环境变量
    if [[ "${TERM:-}" == "dumb" ]]; then
        return 0
    fi
    
    # 6. 检查是否在脚本中运行（通过$0判断）
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        # 在source的脚本中，可能是自动化脚本
        local caller_script="${0##*/}"
        if [[ "$caller_script" =~ (test|spec|ci|deploy|build|automation) ]]; then
            return 0
        fi
    fi
    
    return 1
}

# 检测是否在CI环境中
is_ci_environment() {
    if [[ -n "${CI:-}" || -n "${CONTINUOUS_INTEGRATION:-}" ]]; then
        return 0
    fi
    
    # 检查具体CI平台
    if [[ -n "${GITHUB_ACTIONS:-}" || 
          -n "${GITLAB_CI:-}" || 
          -n "${JENKINS_URL:-}" || 
          -n "${BUILDKITE:-}" || 
          -n "${CIRCLECI:-}" || 
          -n "${TRAVIS:-}" || 
          -n "${APPVEYOR:-}" ]]; then
        return 0
    fi
    
    return 1
}

# 获取CI平台名称
get_ci_platform() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "GitHub Actions"
    elif [[ -n "${GITLAB_CI:-}" ]]; then
        echo "GitLab CI"
    elif [[ -n "${JENKINS_URL:-}" ]]; then
        echo "Jenkins"
    elif [[ -n "${BUILDKITE:-}" ]]; then
        echo "Buildkite"
    elif [[ -n "${CIRCLECI:-}" ]]; then
        echo "CircleCI"
    elif [[ -n "${TRAVIS:-}" ]]; then
        echo "Travis CI"
    elif [[ -n "${APPVEYOR:-}" ]]; then
        echo "AppVeyor"
    elif [[ -n "${CI:-}" ]]; then
        echo "Unknown CI"
    else
        echo "Not CI"
    fi
}

# 检测是否在自动化脚本中
is_automation_context() {
    # 检查调用栈中是否有自动化相关的脚本
    local i
    for ((i=1; i<${#BASH_SOURCE[@]}; i++)); do
        local source_file="${BASH_SOURCE[$i]}"
        local filename="${source_file##*/}"
        
        if [[ "$filename" =~ (test|spec|ci|deploy|build|automation|script) ]]; then
            return 0
        fi
    done
    
    return 1
}

# =====================================================
# 非交互式环境配置
# =====================================================

# 获取非交互式环境的默认配置
get_non_interactive_config() {
    local config_key="$1"
    local default_value="$2"
    
    case "$config_key" in
        "auto_confirm")
            # 在非交互式环境中，默认自动确认安全操作
            echo "${GPF_AUTO_CONFIRM:-true}"
            ;;
        "sync_strategy")
            # 默认同步策略
            echo "${GPF_SYNC_STRATEGY:-base}"
            ;;
        "conflict_resolution")
            # 冲突解决策略
            echo "${GPF_CONFLICT_RESOLUTION:-abort}"
            ;;
        "dependency_selection")
            # 依赖选择策略
            echo "${GPF_DEPENDENCY_SELECTION:-auto}"
            ;;
        "branch_selection")
            # 分支选择策略
            echo "${GPF_BRANCH_SELECTION:-current}"
            ;;
        *)
            echo "$default_value"
            ;;
    esac
}

# 设置非交互式模式
set_non_interactive_mode() {
    export GPF_NON_INTERACTIVE="true"
    
    # 设置默认的非交互式配置
    export GPF_AUTO_CONFIRM="${GPF_AUTO_CONFIRM:-true}"
    export GPF_SYNC_STRATEGY="${GPF_SYNC_STRATEGY:-base}"
    export GPF_CONFLICT_RESOLUTION="${GPF_CONFLICT_RESOLUTION:-abort}"
    export GPF_DEPENDENCY_SELECTION="${GPF_DEPENDENCY_SELECTION:-auto}"
    export GPF_BRANCH_SELECTION="${GPF_BRANCH_SELECTION:-current}"
}

# 禁用非交互式模式
unset_non_interactive_mode() {
    unset GPF_NON_INTERACTIVE
    unset GPF_AUTO_CONFIRM
    unset GPF_SYNC_STRATEGY
    unset GPF_CONFLICT_RESOLUTION
    unset GPF_DEPENDENCY_SELECTION
    unset GPF_BRANCH_SELECTION
}

# =====================================================
# 交互式与非交互式兼容函数
# =====================================================

# 兼容的确认函数
compat_confirm() {
    local message="$1"
    local default="${2:-N}"
    
    if is_non_interactive; then
        local auto_confirm
        auto_confirm=$(get_non_interactive_config "auto_confirm" "false")
        
        if [[ "$auto_confirm" == "true" ]]; then
            echo "ℹ️ 非交互式环境，自动确认: $message" >&2
            return 0
        else
            echo "ℹ️ 非交互式环境，自动拒绝: $message" >&2
            return 1
        fi
    else
        # 交互式环境，使用标准UI确认
        ui_confirm "$message" "$default"
    fi
}

# 兼容的选择函数
compat_select() {
    local title="$1"
    shift
    local options=("$@")
    
    if is_non_interactive; then
        local selection_strategy
        selection_strategy=$(get_non_interactive_config "branch_selection" "first")
        
        case "$selection_strategy" in
            "first")
                echo "ℹ️ 非交互式环境，自动选择第一个选项: ${options[0]}" >&2
                echo 0
                ;;
            "last")
                local last_index=$((${#options[@]} - 1))
                echo "ℹ️ 非交互式环境，自动选择最后一个选项: ${options[$last_index]}" >&2
                echo $last_index
                ;;
            *)
                # 默认选择第一个
                echo "ℹ️ 非交互式环境，默认选择第一个选项: ${options[0]}" >&2
                echo 0
                ;;
        esac
    else
        # 交互式环境，使用标准UI选择
        ui_select_menu "$title" "${options[@]}"
    fi
}

# 兼容的输入函数
compat_input() {
    local message="$1"
    local default="$2"
    
    if is_non_interactive; then
        echo "ℹ️ 非交互式环境，使用默认值: $default" >&2
        echo "$default"
    else
        # 交互式环境，使用标准UI输入
        ui_input "$message" "$default"
    fi
}

# =====================================================
# 环境信息展示
# =====================================================

# 显示当前环境信息
show_environment_info() {
    echo "🔍 环境检测信息:"
    echo
    
    if is_non_interactive; then
        echo "  📋 运行模式: 非交互式"
        
        if is_ci_environment; then
            echo "  🤖 CI平台: $(get_ci_platform)"
        fi
        
        if is_automation_context; then
            echo "  🔧 自动化上下文: 是"
        fi
        
        echo "  ⚙️ 非交互式配置:"
        echo "    • 自动确认: $(get_non_interactive_config "auto_confirm")"
        echo "    • 同步策略: $(get_non_interactive_config "sync_strategy")"
        echo "    • 冲突解决: $(get_non_interactive_config "conflict_resolution")"
        echo "    • 依赖选择: $(get_non_interactive_config "dependency_selection")"
        echo "    • 分支选择: $(get_non_interactive_config "branch_selection")"
    else
        echo "  📋 运行模式: 交互式"
        echo "  💬 用户界面: 可用"
    fi
    
    echo
}

# 验证非交互式环境配置
validate_non_interactive_config() {
    if ! is_non_interactive; then
        return 0
    fi
    
    local errors=0
    
    # 检查必要的配置是否合理
    local conflict_resolution
    conflict_resolution=$(get_non_interactive_config "conflict_resolution")
    
    if [[ "$conflict_resolution" != "abort" && "$conflict_resolution" != "skip" ]]; then
        echo "⚠️ 警告: 非交互式环境中的冲突解决策略可能不安全: $conflict_resolution" >&2
        ((errors++))
    fi
    
    return $errors
}

# =====================================================
# 工具函数
# =====================================================

# 记录非交互式操作日志
log_non_interactive_operation() {
    local operation="$1"
    local details="$2"
    
    if is_non_interactive; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local ci_platform=$(get_ci_platform)
        
        echo "[$timestamp] 非交互式操作: $operation" >&2
        if [[ -n "$details" ]]; then
            echo "[$timestamp] 详情: $details" >&2
        fi
        if [[ "$ci_platform" != "Not CI" ]]; then
            echo "[$timestamp] CI平台: $ci_platform" >&2
        fi
    fi
}

# 在非交互式环境中安全执行命令
safe_non_interactive_exec() {
    local operation="$1"
    shift
    local command_args=("$@")
    
    if is_non_interactive; then
        log_non_interactive_operation "$operation" "执行命令: ${command_args[*]}"
        
        # 检查是否为安全操作
        if [[ "$operation" =~ (delete|remove|clean|force) ]]; then
            local auto_confirm
            auto_confirm=$(get_non_interactive_config "auto_confirm" "false")
            
            if [[ "$auto_confirm" != "true" ]]; then
                echo "❌ 非交互式环境中拒绝执行危险操作: $operation" >&2
                return 1
            fi
        fi
    fi
    
    # 执行命令
    "${command_args[@]}"
}
