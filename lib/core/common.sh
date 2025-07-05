#!/bin/bash
# GPF Core - Common Utilities and Configuration
# 公共工具和配置

set -euo pipefail

# GPF版本信息
readonly GPF_VERSION="1.0.0-dev"
readonly GPF_BUILD_DATE="2025-07-05"

# 颜色配置
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_PURPLE='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_RESET='\033[0m'

# 统一的输出接口
ui_success() {
    echo -e "${COLOR_GREEN}✅ $*${COLOR_RESET}"
}

ui_error() {
    echo -e "${COLOR_RED}❌ $*${COLOR_RESET}" >&2
}

ui_warning() {
    echo -e "${COLOR_YELLOW}⚠️ $*${COLOR_RESET}" >&2
}

ui_info() {
    echo -e "${COLOR_BLUE}💡 $*${COLOR_RESET}"
}

ui_debug() {
    if [[ "${GPF_DEBUG:-}" == "1" ]]; then
        echo -e "${COLOR_PURPLE}🔍 DEBUG: $*${COLOR_RESET}" >&2
    fi
}

# 性能计时工具
declare -A _GPF_TIMERS

timer_start() {
    local timer_name="$1"
    _GPF_TIMERS["$timer_name"]=$(date +%s%N)
}

timer_end() {
    local timer_name="$1"
    local start_time="${_GPF_TIMERS[$timer_name]:-}"
    
    if [[ -z "$start_time" ]]; then
        ui_error "计时器 $timer_name 未启动"
        return 1
    fi
    
    local end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    ui_debug "$timer_name 执行时间: ${duration_ms}ms"
    unset _GPF_TIMERS["$timer_name"]
    echo "$duration_ms"
}

# 错误处理
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    ui_error "脚本执行失败，行号: $line_number, 退出码: $exit_code"
    
    # 如果在调试模式，显示调用栈
    if [[ "${GPF_DEBUG:-}" == "1" ]]; then
        ui_debug "调用栈:"
        local frame=0
        while caller $frame; do
            frame=$((frame + 1))
        done
    fi
    
    exit $exit_code
}

# 设置错误处理
trap 'handle_error $LINENO' ERR

# 日志记录
log_operation() {
    local operation="$1"
    local details="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "${GPF_LOG_FILE:-}" ]]; then
        echo "[$timestamp] $operation: $details" >> "$GPF_LOG_FILE"
    fi
    
    ui_debug "操作日志: $operation - $details"
}

# 环境变量验证
validate_environment() {
    # 检查必要的环境变量
    if [[ -z "${HOME:-}" ]]; then
        ui_error "HOME 环境变量未设置"
        return 1
    fi
    
    # 检查必要的命令
    local required_commands=("git" "bash" "awk" "grep" "sed")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            ui_error "必需命令 $cmd 未找到"
            return 1
        fi
    done
    
    # 检查Git版本
    local git_version
    git_version=$(git --version | awk '{print $3}')
    local git_major
    git_major=$(echo "$git_version" | cut -d. -f1)
    local git_minor
    git_minor=$(echo "$git_version" | cut -d. -f2)
    
    if [[ "$git_major" -lt 2 ]] || [[ "$git_major" -eq 2 && "$git_minor" -lt 22 ]]; then
        ui_warning "Git版本较低 ($git_version)，建议升级到 2.22+"
    fi
    
    return 0
}

# 初始化函数
gpf_init() {
    # 验证环境
    validate_environment || return 1
    
    # 设置调试模式
    if [[ "${1:-}" == "--debug" ]]; then
        export GPF_DEBUG=1
        ui_debug "调试模式已启用"
    fi
    
    # 记录初始化
    log_operation "INIT" "GPF v$GPF_VERSION 初始化完成"
    
    return 0
}

# 安全地执行命令并记录
safe_execute() {
    local description="$1"
    shift
    
    ui_debug "执行: $description"
    log_operation "EXEC" "$description: $*"
    
    if "$@"; then
        ui_debug "执行成功: $description"
        return 0
    else
        local exit_code=$?
        ui_error "执行失败: $description (退出码: $exit_code)"
        return $exit_code
    fi
}

# JSON工具函数
json_escape() {
    local input="$1"
    # 转义JSON特殊字符
    echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

json_extract_value() {
    local json="$1"
    local key="$2"
    
    echo "$json" | grep -o "\"$key\":[^,}]*" | cut -d: -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
}

# 平台兼容性工具
get_platform() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

# 获取脚本目录
get_script_dir() {
    local script_path="${BASH_SOURCE[0]}"
    while [[ -L "$script_path" ]]; do
        local dir
        dir=$(cd -P "$(dirname "$script_path")" && pwd)
        script_path=$(readlink "$script_path")
        [[ "$script_path" != /* ]] && script_path="$dir/$script_path"
    done
    cd -P "$(dirname "$script_path")" && pwd
}

# 显示版本信息
show_version() {
    cat << EOF
GPF (Git PR Flow) v$GPF_VERSION
构建日期: $GPF_BUILD_DATE
平台: $(get_platform)
Git版本: $(git --version | awk '{print $3}')
EOF
}

# 导入原子层方法
source_atomic_modules() {
    local script_dir
    script_dir=$(get_script_dir)
    local atomic_dir="$script_dir/atomic"
    
    if [[ -d "$atomic_dir" ]]; then
        for atomic_file in "$atomic_dir"/*.sh; do
            if [[ -f "$atomic_file" ]]; then
                source "$atomic_file"
                ui_debug "已加载原子模块: $(basename "$atomic_file")"
            fi
        done
    else
        ui_warning "原子层目录不存在: $atomic_dir"
    fi
}