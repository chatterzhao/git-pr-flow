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