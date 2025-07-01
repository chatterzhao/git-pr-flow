#!/usr/bin/env bash

# Git PR Flow - 用户界面工具
# 提供交互式界面、颜色输出、进度显示等功能

# 避免重复加载
if [[ -n "${GPF_UI_LOADED:-}" ]]; then
    return 0
fi
GPF_UI_LOADED=1

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# 图标定义
readonly ICON_SUCCESS="✅"
readonly ICON_WARNING="⚠️"
readonly ICON_ERROR="❌"
readonly ICON_INFO="ℹ️"
readonly ICON_LOADING="🔄"
readonly ICON_BRANCH="🌿"
readonly ICON_WORKTREE="🏠"
readonly ICON_EPIC="🚀"
readonly ICON_SYNC="🔄"
readonly ICON_PR="📋"
readonly ICON_CODE="💻"

# 基础颜色输出函数
ui_red() {
    echo -e "${RED}$*${NC}"
}

ui_green() {
    echo -e "${GREEN}$*${NC}"
}

ui_yellow() {
    echo -e "${YELLOW}$*${NC}"
}

ui_blue() {
    echo -e "${BLUE}$*${NC}"
}

ui_purple() {
    echo -e "${PURPLE}$*${NC}"
}

ui_cyan() {
    echo -e "${CYAN}$*${NC}"
}

ui_bold() {
    echo -e "${BOLD}$*${NC}"
}

# 状态输出函数
ui_success() {
    echo -e "${GREEN}${ICON_SUCCESS}${NC} $*"
}

ui_warning() {
    echo -e "${YELLOW}${ICON_WARNING}${NC} $*"
}

ui_error() {
    echo -e "${RED}${ICON_ERROR}${NC} $*" >&2
}

ui_info() {
    echo -e "${BLUE}${ICON_INFO}${NC} $*"
}

ui_loading() {
    echo -e "${YELLOW}${ICON_LOADING}${NC} $*"
}

# 标题和分隔符
ui_header() {
    echo
    ui_bold "=== $* ==="
    echo
}

ui_subheader() {
    echo
    ui_cyan "📋 $*"
    echo
}

ui_separator() {
    echo "────────────────────────────────────────"
}

# 列表输出
ui_list_item() {
    echo "  ├─ $*"
}

ui_list_item_last() {
    echo "  └─ $*"
}

ui_tree_branch() {
    echo "  ├── $*"
}

ui_tree_last() {
    echo "  └── $*"
}

# 交互式选择菜单
ui_select_menu() {
    local title="$1"
    shift
    local options=("$@")
    
    # 检查是否为非交互式环境
    if [[ ! -t 0 ]] || [[ -n "${CI:-}" ]] || [[ -n "${BATCH_MODE:-}" ]]; then
        ui_error "非交互式环境无法显示选择菜单"
        ui_info "请使用具体的参数调用命令，例如："
        ui_info "  gpf clean --dry-run    # 预检模式"
        ui_info "  gpf clean --all        # 清理所有"
        ui_info "  gpf clean --help       # 显示帮助"
        return 1
    fi
    
    ui_subheader "$title"
    
    for i in "${!options[@]}"; do
        echo "  $(($i + 1)). ${options[$i]}"
    done
    echo
    
    local attempt_count=0
    local max_attempts=10
    
    while true; do
        # 防止无限循环，设置最大尝试次数
        if [[ $attempt_count -ge $max_attempts ]]; then
            ui_error "尝试次数过多，退出选择菜单"
            ui_info "请检查输入环境或使用具体参数调用命令"
            return 1
        fi
        
        read -p "请选择 (1-${#options[@]}): " -r choice
        ((attempt_count++))
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            echo $((choice - 1))
            return 0
        else
            ui_error "无效选择，请输入 1-${#options[@]} 之间的数字"
        fi
    done
}

# 进度条显示
ui_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    
    local percentage=$((current * 100 / total))
    local bar_length=30
    local filled_length=$((percentage * bar_length / 100))
    
    printf "\r${BLUE}${ICON_LOADING}${NC} %s [" "$message"
    
    for ((i = 0; i < filled_length; i++)); do
        printf "█"
    done
    
    for ((i = filled_length; i < bar_length; i++)); do
        printf "░"
    done
    
    printf "] %d%% (%d/%d)" "$percentage" "$current" "$total"
    
    if [[ "$current" -eq "$total" ]]; then
        echo
    fi
}

# Epic状态显示
ui_epic_status() {
    local epic_name="$1"
    local progress="$2"
    local total_features="$3"
    local completed_features="$4"
    
    echo
    ui_bold "${ICON_EPIC} Epic: $epic_name"
    echo "  进度: ${progress}% (${completed_features}/${total_features} 功能完成)"
    echo
}

# 分支状态树形显示
ui_branch_tree() {
    local base_branch="$1"
    shift
    local branches=("$@")
    
    echo "${ICON_BRANCH} $base_branch (基础分支)"
    
    for i in "${!branches[@]}"; do
        local branch="${branches[$i]}"
        local status_icon
        
        # 这里可以根据实际分支状态设置不同图标
        if [[ $((RANDOM % 3)) -eq 0 ]]; then
            status_icon="${ICON_SUCCESS}"
        elif [[ $((RANDOM % 3)) -eq 1 ]]; then
            status_icon="${ICON_LOADING}"
        else
            status_icon="${ICON_CODE}"
        fi
        
        if [[ $i -eq $((${#branches[@]} - 1)) ]]; then
            echo "  └── ${status_icon} $branch"
        else
            echo "  ├── ${status_icon} $branch"
        fi
    done
}

# 工作树状态显示
ui_worktree_status() {
    local worktree_path="$1"
    local branch="$2"
    local status="$3"
    
    local status_icon
    case "$status" in
        "active")
            status_icon="${ICON_SUCCESS}"
            ;;
        "syncing")
            status_icon="${ICON_LOADING}"
            ;;
        "conflict")
            status_icon="${ICON_WARNING}"
            ;;
        *)
            status_icon="${ICON_INFO}"
            ;;
    esac
    
    echo "  ${status_icon} ${ICON_WORKTREE} $worktree_path"
    echo "    └─ 分支: $branch"
}

# 确认提示框
ui_confirm() {
    local message="$1"
    local default="${2:-N}"
    
    local prompt_color="${YELLOW}"
    local prompt_icon="❓"
    
    if [[ "$default" == "Y" ]]; then
        prompt="$message [Y/n] "
    else
        prompt="$message [y/N] "
    fi
    
    echo -e "${prompt_color}${prompt_icon}${NC} $prompt" | tr -d '\n'
    read -r response
    
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

# 输入提示框
ui_input() {
    local message="$1"
    local default="$2"
    
    if [[ -n "$default" ]]; then
        echo -e "${CYAN}❓${NC} $message [$default]: " | tr -d '\n'
    else
        echo -e "${CYAN}❓${NC} $message: " | tr -d '\n'
    fi
    
    read -r response
    
    if [[ -z "$response" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$response"
    fi
}

# 多行信息框
ui_info_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo
    echo "┌─────────────────────────────────────────────┐"
    printf "│ %-43s │\n" "$title"
    echo "├─────────────────────────────────────────────┤"
    
    for line in "${lines[@]}"; do
        printf "│ %-43s │\n" "$line"
    done
    
    echo "└─────────────────────────────────────────────┘"
    echo
}

# 警告框
ui_warning_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo
    ui_yellow "┌─ ⚠️  $title ─────────────────────────────────┐"
    
    for line in "${lines[@]}"; do
        ui_yellow "│ $line"
    done
    
    ui_yellow "└─────────────────────────────────────────────┘"
    echo
}

# 成功框
ui_success_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo
    ui_green "┌─ ✅ $title ─────────────────────────────────┐"
    
    for line in "${lines[@]}"; do
        ui_green "│ $line"
    done
    
    ui_green "└─────────────────────────────────────────────┘"
    echo
}