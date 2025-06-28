#!/usr/bin/env bash

# Git PR Flow - 通用工具函数
# 提供项目通用的工具函数和常量定义

# 调试日志函数
log_debug() {
    if [[ "${GIT_PR_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

log_info() {
    echo "INFO: $*" >&2
}

log_warn() {
    echo "WARN: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# 字符串工具函数
trim() {
    local var="$*"
    # 移除开头空白
    var="${var#"${var%%[![:space:]]*}"}"
    # 移除结尾空白
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# 分支名与目录名转换
branch_to_worktree_path() {
    local branch_name="$1"
    echo ".worktrees/${branch_name//\//--}"
}

worktree_path_to_branch() {
    local worktree_path="$1"
    # 移除 .worktrees/ 前缀
    local branch_part="${worktree_path#.worktrees/}"
    # 将 -- 替换为 /
    echo "${branch_part//--/\/}"
}

# Epic名称标准化 (确保有epic/前缀)
normalize_epic_name() {
    local epic_name="$1"
    if [[ "$epic_name" =~ ^epic/ ]]; then
        echo "$epic_name"
    else
        echo "epic/$epic_name"
    fi
}

# 去除epic/前缀获取基础名称
get_base_epic_name() {
    local epic_name="$1"
    echo "${epic_name#epic/}"
}

# 子功能名称标准化 (确保有epic/前缀)
normalize_feature_name() {
    local feature_name="$1"
    if [[ "$feature_name" =~ ^epic/ ]]; then
        echo "$feature_name"
    else
        echo "epic/$feature_name"
    fi
}

# 时间戳函数
current_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

current_local_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# 确保目录存在
ensure_dir() {
    local dir_path="$1"
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
        log_debug "创建目录: $dir_path"
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 确认对话框
confirm() {
    local message="$1"
    local default="${2:-N}"
    
    local prompt
    if [[ "$default" == "Y" ]]; then
        prompt="$message [Y/n] "
    else
        prompt="$message [y/N] "
    fi
    
    read -p "$prompt" -r response
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查文件是否存在且可读
file_readable() {
    [[ -f "$1" && -r "$1" ]]
}

# 检查目录是否存在且可写
dir_writable() {
    [[ -d "$1" && -w "$1" ]]
}

# 创建目录（如果不存在）
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_debug "创建目录: $dir"
    fi
}

# 安全删除目录
safe_remove_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        if confirm "确定要删除目录 '$dir' 吗？"; then
            rm -rf "$dir"
            log_info "已删除目录: $dir"
        else
            log_info "取消删除操作"
            return 1
        fi
    fi
}

# 获取当前时间戳
current_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 获取ISO格式时间戳
current_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 检查是否为空字符串
is_empty() {
    [[ -z "${1:-}" ]]
}

# 检查是否为有效的分支名
is_valid_branch_name() {
    local branch_name="$1"
    
    # Git分支名基本规则检查
    if [[ -z "$branch_name" ]]; then
        return 1
    fi
    
    # 不能以 . 或 / 开头
    if [[ "$branch_name" =~ ^[./] ]]; then
        return 1
    fi
    
    # 不能包含 .. 或以 / 结尾
    if [[ "$branch_name" =~ \.\. ]] || [[ "$branch_name" =~ /$ ]]; then
        return 1
    fi
    
    # 不能包含控制字符或特殊字符
    if [[ "$branch_name" =~ [[:cntrl:][:space:]] ]] || [[ "$branch_name" =~ [\~\^:\?*\[] ]]; then
        return 1
    fi
    
    return 0
}

# Epic名称验证
is_valid_epic_name() {
    local epic_name="$1"
    
    # 基本检查
    if [[ -z "$epic_name" ]]; then
        return 1
    fi
    
    # 长度检查 (3-50字符)
    if [[ ${#epic_name} -lt 3 || ${#epic_name} -gt 50 ]]; then
        return 1
    fi
    
    # 格式检查: 只允许小写字母、数字、连字符
    if [[ ! "$epic_name" =~ ^[a-z0-9-]+$ ]]; then
        return 1
    fi
    
    # 不能以连字符开头或结尾
    if [[ "$epic_name" =~ ^- ]] || [[ "$epic_name" =~ -$ ]]; then
        return 1
    fi
    
    # 不能包含连续的连字符
    if [[ "$epic_name" =~ -- ]]; then
        return 1
    fi
    
    return 0
}

# 数组包含检查
array_contains() {
    local element="$1"
    shift
    local array=("$@")
    
    for item in "${array[@]}"; do
        if [[ "$item" == "$element" ]]; then
            return 0
        fi
    done
    return 1
}

# 获取数组长度
array_length() {
    local -n arr_ref=$1
    echo "${#arr_ref[@]}"
}

# 等待用户按键
wait_for_key() {
    local message="${1:-按任意键继续...}"
    read -n 1 -s -r -p "$message"
    echo
}

# 确保在项目根目录执行
ensure_project_root_directory() {
    local current_dir=$(pwd)
    local git_root
    
    # 获取Git项目根目录
    if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        ui_error "当前不在Git仓库中"
        exit 1
    fi
    
    # 检查是否在worktree目录中
    if [[ "$current_dir" =~ /.worktrees/ ]]; then
        ui_info "检测到在worktree目录中，自动切换到项目根目录"
        ui_info "从: $current_dir"
        ui_info "到: $git_root"
        
        # 切换到项目根目录
        cd "$git_root" || {
            ui_error "无法切换到项目根目录: $git_root"
            exit 1
        }
        
        ui_success "已切换到项目根目录"
    elif [[ "$current_dir" != "$git_root" ]]; then
        ui_warn "当前目录不是项目根目录"
        ui_info "当前: $current_dir"
        ui_info "根目录: $git_root"
        ui_info "建议在项目根目录执行gpf命令"
    fi
}