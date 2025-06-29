#!/usr/bin/env bash

# Git PR Flow - code命令实现
# VS Code集成，智能打开功能分支工作环境

# 引入环境检测工具
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../utils/environment.sh"

# code命令主函数
cmd_code() {
    local feature_name="${1:-}"
    
    # 检查VS Code是否可用
    if ! command_exists code; then
        ui_error "VS Code未安装或不在PATH中"
        ui_info "请安装VS Code并确保'code'命令可用"
        ui_info "安装指引: https://code.visualstudio.com/docs/setup/mac#_launching-from-the-command-line"
        return 1
    fi
    
    # 检查Epic配置
    if ! config_epic_exists; then
        ui_warning "未找到Epic配置，打开当前目录"
        open_current_directory_in_vscode
        return 0
    fi
    
    if [[ -z "$feature_name" ]]; then
        handle_code_interactive
    else
        open_feature_in_vscode "$feature_name"
    fi
}

# 交互式VS Code打开
handle_code_interactive() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "VS Code集成"
    ui_info "当前Epic: $epic_name"
    
    # 获取可打开的功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_warning "没有找到功能分支"
        if ui_confirm "在当前目录打开VS Code？"; then
            open_current_directory_in_vscode
        fi
        return 0
    fi
    
    # 构建选项列表
    local options=()
    local worktree_paths=()
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local worktree_path
            worktree_path=$(branch_to_worktree_path "$branch")
            
            if [[ -d "$worktree_path" ]]; then
                options+=("🏠 $branch (工作树)")
                worktree_paths+=("$worktree_path")
            else
                options+=("📋 $branch (仅分支)")
                worktree_paths+=("")
            fi
        fi
    done <<< "$feature_branches"
    
    # 添加其他选项
    options+=("📁 当前目录")
    options+=("🔧 生成VS Code工作区")
    options+=("取消操作")
    
    local choice
    choice=$(ui_select_menu "选择要打开的环境" "${options[@]}")
    
    local feature_count=${#worktree_paths[@]}
    
    if [[ $choice -lt $feature_count ]]; then
        # 选择了功能分支
        local selected_path="${worktree_paths[$choice]}"
        if [[ -n "$selected_path" ]]; then
            open_directory_in_vscode "$selected_path"
        else
            ui_warning "功能分支没有工作树，请先运行 gpf start"
        fi
    elif [[ $choice -eq $feature_count ]]; then
        # 当前目录
        open_current_directory_in_vscode
    elif [[ $choice -eq $((feature_count + 1)) ]]; then
        # 生成工作区
        source "$PROJECT_ROOT/lib/commands/workspace.sh"
        cmd_workspace
    else
        # 取消
        ui_info "取消操作"
    fi
}

# 打开指定功能在VS Code中
open_feature_in_vscode() {
    local feature_name="$1"
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 标准化功能名称
    if [[ ! "$feature_name" =~ ^$epic_name/ ]]; then
        feature_name="$epic_name/$feature_name"
    fi
    
    if ! git_branch_exists "$feature_name"; then
        ui_error "功能分支不存在: $feature_name"
        return 1
    fi
    
    local worktree_path
    worktree_path=$(branch_to_worktree_path "$feature_name")
    
    if [[ ! -d "$worktree_path" ]]; then
        ui_error "功能分支工作树不存在: $worktree_path"
        ui_info "请先运行: gpf start $feature_name"
        return 1
    fi
    
    open_directory_in_vscode "$worktree_path"
}

# 在VS Code中打开目录
open_directory_in_vscode() {
    local dir_path="$1"
    
    ui_loading "在VS Code中打开: $dir_path"
    
    if code "$dir_path"; then
        ui_success "✅ VS Code已打开: $dir_path"
        ui_info "💡 提示: Git面板将显示当前功能的文件变更"
    else
        ui_error "❌ 无法在VS Code中打开目录"
    fi
}

# 在VS Code中打开当前目录
open_current_directory_in_vscode() {
    open_directory_in_vscode "$(pwd)"
}