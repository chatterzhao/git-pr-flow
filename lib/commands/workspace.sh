#!/usr/bin/env bash

# Git PR Flow - workspace命令实现
# VS Code多Epic工作区生成和管理

# workspace命令主函数
cmd_workspace() {
    local action="${1:-generate}"
    
    case "$action" in
        "generate")
            generate_vscode_workspace
            ;;
        "open")
            open_existing_workspace
            ;;
        "update")
            update_workspace_config
            ;;
        *)
            ui_error "无效的workspace操作: $action"
            ui_info "支持的操作: generate, open, update"
            ui_info "用法示例:"
            ui_info "  git-pr-flow workspace generate  # 生成VS Code工作区"
            ui_info "  git-pr-flow workspace open      # 打开现有工作区"
            ui_info "  git-pr-flow workspace update    # 更新工作区配置"
            return 1
            ;;
    esac
}

# 生成VS Code工作区
generate_vscode_workspace() {
    ui_header "生成VS Code多Epic工作区"
    
    # 检查当前环境
    local workspace_name project_name
    project_name=$(basename "$(git rev-parse --show-toplevel)")
    workspace_name="$project_name-git-pr-flow.code-workspace"
    
    ui_info "项目: $project_name"
    ui_info "工作区文件: $workspace_name"
    echo
    
    # 分析现有工作环境
    local workspace_config
    workspace_config=$(analyze_workspace_structure)
    
    # 显示工作区预览
    show_workspace_preview "$workspace_config"
    
    if ! ui_confirm "生成VS Code工作区配置？"; then
        ui_info "取消工作区生成"
        return 0
    fi
    
    # 生成工作区文件
    create_workspace_file "$workspace_name" "$workspace_config"
}

# 分析工作区结构
analyze_workspace_structure() {
    local folders=()
    local main_repo
    main_repo=$(git rev-parse --show-toplevel)
    
    # 添加主仓库
    folders+=("{\"name\": \"📁 主仓库\", \"path\": \"$main_repo\"}")
    
    # 添加所有工作树
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local worktree_path="${BASH_REMATCH[1]}"
            
            # 跳过主仓库
            if [[ "$worktree_path" == "$main_repo" ]]; then
                continue
            fi
            
            local branch_name display_name
            branch_name=$(git_worktree_branch "$worktree_path")
            
            # 生成友好的显示名称
            if [[ "$branch_name" =~ / ]]; then
                display_name="🚀 ${branch_name}"
            else
                display_name="🌿 ${branch_name}"
            fi
            
            folders+=("{\"name\": \"$display_name\", \"path\": \"$worktree_path\"}")
        fi
    done <<< "$worktree_info"
    
    # 构建JSON配置
    local folders_json
    folders_json=$(IFS=','; echo "${folders[*]}")
    
    cat << EOF
{
    "folders": [$folders_json],
    "settings": {
        "git.autoRepositoryDetection": "subFolders",
        "git.scanRepositories": ["$main_repo", "$main_repo/.worktrees"],
        "files.exclude": {
            "**/.git": false
        },
        "search.exclude": {
            "**/node_modules": true,
            "**/.git": true
        }
    },
    "extensions": {
        "recommendations": [
            "eamodio.gitlens",
            "ms-vscode.vscode-git-graph",
            "github.vscode-pull-request-github"
        ]
    }
}
EOF
}

# 显示工作区预览
show_workspace_preview() {
    local config="$1"
    
    ui_subheader "工作区结构预览"
    
    # 解析并显示文件夹
    echo "$config" | grep '"name":' | sed 's/.*"name": "\([^"]*\)".*/  \1/' | head -20
    
    local folder_count
    folder_count=$(echo "$config" | grep -c '"name":' || echo "0")
    
    echo
    echo "  📊 总计: $folder_count 个文件夹"
    echo "  🔧 包含推荐扩展和Git配置"
    echo "  🎯 优化的多仓库开发体验"
    echo
}

# 创建工作区文件
create_workspace_file() {
    local workspace_name="$1"
    local config="$2"
    
    ui_loading "生成工作区文件: $workspace_name"
    
    # 写入工作区文件
    echo "$config" | jq . > "$workspace_name" 2>/dev/null || {
        # 如果jq不可用，直接写入
        echo "$config" > "$workspace_name"
    }
    
    if [[ -f "$workspace_name" ]]; then
        ui_success "✅ 工作区文件已生成: $workspace_name"
        echo
        
        # 提供后续操作选项
        ui_subheader "后续操作"
        echo "  💻 打开工作区: code $workspace_name"
        echo "  📝 编辑配置: 可手动编辑工作区文件"
        echo "  🔄 更新配置: git-pr-flow workspace update"
        echo
        
        if command_exists code && ui_confirm "现在在VS Code中打开工作区？"; then
            open_workspace_in_vscode "$workspace_name"
        fi
    else
        ui_error "❌ 工作区文件生成失败"
    fi
}

# 在VS Code中打开工作区
open_workspace_in_vscode() {
    local workspace_file="$1"
    
    ui_loading "在VS Code中打开工作区"
    
    if code "$workspace_file"; then
        ui_success "✅ VS Code工作区已打开"
        ui_info "💡 提示: 所有Epic分支现在都在一个窗口中可见"
    else
        ui_error "❌ 无法打开VS Code工作区"
    fi
}

# 打开现有工作区
open_existing_workspace() {
    ui_subheader "打开现有工作区"
    
    # 查找现有工作区文件
    local workspace_files
    workspace_files=$(find . -maxdepth 1 -name "*.code-workspace" -type f || true)
    
    if [[ -z "$workspace_files" ]]; then
        ui_warning "未找到工作区文件"
        if ui_confirm "生成新的工作区？"; then
            generate_vscode_workspace
        fi
        return 0
    fi
    
    # 显示可用的工作区文件
    local files_array=()
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            files_array+=("$file")
        fi
    done <<< "$workspace_files"
    
    if [[ ${#files_array[@]} -eq 1 ]]; then
        # 只有一个工作区文件，直接打开
        open_workspace_in_vscode "${files_array[0]}"
    else
        # 多个工作区文件，让用户选择
        files_array+=("取消操作")
        
        local choice
        choice=$(ui_select_menu "选择工作区文件" "${files_array[@]}")
        
        if [[ $choice -eq $((${#files_array[@]} - 1)) ]]; then
            ui_info "取消操作"
        else
            open_workspace_in_vscode "${files_array[$choice]}"
        fi
    fi
}

# 更新工作区配置
update_workspace_config() {
    ui_subheader "更新工作区配置"
    
    # 查找现有工作区文件
    local workspace_files
    workspace_files=$(find . -maxdepth 1 -name "*.code-workspace" -type f | head -1)
    
    if [[ -z "$workspace_files" ]]; then
        ui_warning "未找到工作区文件"
        if ui_confirm "生成新的工作区？"; then
            generate_vscode_workspace
        fi
        return 0
    fi
    
    ui_info "更新工作区: $workspace_files"
    
    # 备份现有文件
    local backup_file="${workspace_files}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$workspace_files" "$backup_file"
    ui_info "已备份到: $backup_file"
    
    # 重新生成配置
    local workspace_config
    workspace_config=$(analyze_workspace_structure)
    
    # 更新文件
    echo "$workspace_config" | jq . > "$workspace_files" 2>/dev/null || {
        echo "$workspace_config" > "$workspace_files"
    }
    
    ui_success "✅ 工作区配置已更新"
    ui_info "💡 如需恢复，使用备份文件: $backup_file"
}