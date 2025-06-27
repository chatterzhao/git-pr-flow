#!/usr/bin/env bash

# Git PR Flow - init命令实现
# 初始化Epic开发环境，支持基分支智能检测和配置文件生成

# init命令主函数
cmd_init() {
    local epic_name="$1"
    
    # 如果没有提供Epic名称，显示现有配置或提示输入
    if [[ -z "$epic_name" ]]; then
        if ! handle_init_interactive; then
            return 1
        fi
        return 0
    fi
    
    # 验证Epic名称
    if ! is_valid_epic_name "$epic_name"; then
        ui_error "无效的Epic名称: $epic_name"
        ui_info "Epic名称应该使用小写字母、数字和连字符，如: auth, user-profile, payment-system"
        return 1
    fi
    
    # 检查是否已存在Epic配置
    if config_epic_exists; then
        handle_existing_epic_config "$epic_name"
        return $?
    fi
    
    # 执行新Epic初始化
    init_new_epic "$epic_name"
}

# 交互式初始化处理
handle_init_interactive() {
    ui_header "Epic开发环境初始化"
    
    # 检查现有配置
    if config_epic_exists; then
        ui_subheader "检测到已有Epic配置"
        config_epic_show
        
        local options=(
            "使用现有配置 (快速启动)"
            "重新配置 (覆盖现有配置)"
            "查看配置详情"
            "取消操作"
        )
        
        local choice
        choice=$(ui_select_menu "选择操作" "${options[@]}")
        
        case $choice in
            0) # 使用现有配置
                ui_success "使用现有Epic配置"
                return 0
                ;;
            1) # 重新配置
                local epic_name
                epic_name=$(config_epic_get "epic_name")
                if ui_confirm "确定要重新配置Epic '$epic_name' 吗？"; then
                    init_new_epic "$epic_name"
                    return $?
                else
                    ui_info "取消重新配置"
                    return 1
                fi
                ;;
            2) # 查看配置详情
                show_detailed_config
                return 0
                ;;
            3) # 取消操作
                ui_info "取消初始化操作"
                return 1
                ;;
        esac
    else
        # 没有现有配置，提示创建新Epic
        ui_info "未发现Epic配置，开始新Epic创建流程"
        
        local epic_name
        while true; do
            epic_name=$(ui_input "Epic名称" "")
            if [[ -n "$epic_name" ]] && is_valid_epic_name "$epic_name"; then
                break
            else
                ui_error "请输入有效的Epic名称 (小写字母、数字、连字符)"
            fi
        done
        
        init_new_epic "$epic_name"
        return $?
    fi
}

# 处理已存在的Epic配置
handle_existing_epic_config() {
    local new_epic_name="$1"
    local existing_epic_name
    existing_epic_name=$(config_epic_get "epic_name")
    
    if [[ "$new_epic_name" == "$existing_epic_name" ]]; then
        ui_info "Epic '$new_epic_name' 已经初始化"
        config_epic_show
        
        if ui_confirm "是否要重新初始化？"; then
            init_new_epic "$new_epic_name"
            return $?
        else
            return 0
        fi
    else
        ui_warning "当前目录已有不同的Epic配置: $existing_epic_name"
        ui_info "要初始化的Epic: $new_epic_name"
        
        if ui_confirm "是否要替换现有配置？"; then
            init_new_epic "$new_epic_name"
            return $?
        else
            ui_info "保持现有Epic配置: $existing_epic_name"
            return 1
        fi
    fi
}

# 初始化新Epic
init_new_epic() {
    local epic_name="$1"
    
    ui_loading "正在初始化Epic: $epic_name"
    
    # 1. 获取Epic描述
    local description
    description=$(ui_input "Epic描述" "")
    if [[ -z "$description" ]]; then
        description="$epic_name Epic功能开发"
    fi
    
    # 2. 智能检测和选择基分支
    local base_branch
    if ! base_branch=$(select_base_branch); then
        ui_error "基分支选择失败"
        return 1
    fi
    
    # 3. 生成工作树路径
    local worktree_base_path
    worktree_base_path=$(generate_worktree_path "$epic_name")
    
    # 4. 确认配置
    ui_subheader "配置确认"
    echo "  Epic名称: $epic_name"
    echo "  描述: $description"
    echo "  基础分支: $base_branch"
    echo "  工作树路径: $worktree_base_path"
    echo
    
    if ! ui_confirm "确认创建Epic配置？"; then
        ui_info "取消Epic创建"
        return 1
    fi
    
    # 5. 创建Epic配置文件
    config_epic_create "$epic_name" "$description" "$base_branch" "$worktree_base_path"
    
    # 6. 创建工作树目录结构
    ensure_dir "$(dirname "$worktree_base_path")"
    
    # 7. 显示后续步骤
    show_next_steps "$epic_name"
    
    ui_success "Epic '$epic_name' 初始化完成！"
    return 0
}

# 智能基分支选择
select_base_branch() {
    ui_subheader "基分支选择"
    
    # 检测项目中现有的重要分支
    local detected_branches=()
    local branch_descriptions=()
    
    # 检测常见的主分支
    if git_branch_exists "main"; then
        detected_branches+=("main")
        branch_descriptions+=("main (GitHub主分支) ⭐ 推荐")
    fi
    
    if git_branch_exists "master"; then
        detected_branches+=("master")
        branch_descriptions+=("master (传统主分支)")
    fi
    
    if git_branch_exists "develop"; then
        detected_branches+=("develop")
        branch_descriptions+=("develop (GitFlow开发分支) ⭐ 推荐")
    fi
    
    if git_branch_exists "staging"; then
        detected_branches+=("staging")
        branch_descriptions+=("staging (预发布分支)")
    fi
    
    # 检测release分支
    local release_branches
    release_branches=$(git_list_branches | grep "^release/" | head -3)
    if [[ -n "$release_branches" ]]; then
        while IFS= read -r branch; do
            detected_branches+=("$branch")
            branch_descriptions+=("$branch (发布分支)")
        done <<< "$release_branches"
    fi
    
    # 添加自定义选项
    branch_descriptions+=("自定义分支...")
    
    if [[ ${#detected_branches[@]} -eq 0 ]]; then
        ui_warning "未检测到标准分支，当前分支: $(git_current_branch)"
        detected_branches+=("$(git_current_branch)")
        branch_descriptions=("$(git_current_branch) (当前分支)" "自定义分支...")
    fi
    
    ui_info "检测到以下分支："
    
    local choice
    choice=$(ui_select_menu "选择基础分支" "${branch_descriptions[@]}")
    
    if [[ $choice -eq $((${#branch_descriptions[@]} - 1)) ]]; then
        # 自定义分支
        local custom_branch
        while true; do
            custom_branch=$(ui_input "输入自定义分支名" "")
            if [[ -n "$custom_branch" ]]; then
                if git_branch_exists "$custom_branch"; then
                    echo "$custom_branch"
                    return 0
                else
                    ui_error "分支 '$custom_branch' 不存在"
                fi
            fi
        done
    else
        echo "${detected_branches[$choice]}"
        return 0
    fi
}

# 生成工作树路径
generate_worktree_path() {
    local epic_name="$1"
    echo ".worktrees/$epic_name"
}

# 显示详细配置信息
show_detailed_config() {
    ui_header "Epic配置详情"
    
    if ! config_epic_validate; then
        return 1
    fi
    
    local epic_name description base_branch worktree_path created_at config_version
    epic_name=$(config_epic_get "epic_name")
    description=$(config_epic_get "description")
    base_branch=$(config_epic_get "base_branch")
    worktree_path=$(config_epic_get "worktree_path")
    created_at=$(config_epic_get "created_at")
    config_version=$(config_epic_get "config_version")
    
    echo "📋 基本信息:"
    echo "  Epic名称: $epic_name"
    echo "  描述: $description"
    echo "  基础分支: $base_branch"
    echo "  工作树路径: $worktree_path"
    echo "  配置版本: $config_version"
    echo "  创建时间: $created_at"
    echo
    
    echo "🔧 自动化设置:"
    echo "  自动分支切换: $(config_epic_get "auto_switch_branch")"
    echo "  自动同步: $(config_epic_get "auto_sync")"
    echo "  自动清理: $(config_epic_get "auto_cleanup")"
    echo
    
    echo "🔄 工作流设置:"
    echo "  工作流类型: $(config_epic_get "workflow_type")"
    echo "  PR策略: $(config_epic_get "pr_strategy")"
    echo
    
    # 检查工作树状态
    if [[ -d "$worktree_path" ]]; then
        ui_success "工作树目录存在: $worktree_path"
        
        # 列出现有的子功能分支
        local feature_branches
        feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
        if [[ -n "$feature_branches" ]]; then
            echo "🌿 子功能分支:"
            while IFS= read -r branch; do
                local worktree_branch_path
                worktree_branch_path=$(branch_to_worktree_path "$branch")
                if [[ -d "$worktree_branch_path" ]]; then
                    echo "  ✅ $branch ($worktree_branch_path)"
                else
                    echo "  📋 $branch (无工作树)"
                fi
            done <<< "$feature_branches"
        else
            echo "🌿 子功能分支: 暂无"
        fi
    else
        ui_warning "工作树目录不存在: $worktree_path"
    fi
}

# 显示后续步骤
show_next_steps() {
    local epic_name="$1"
    
    ui_success_box "Epic '$epic_name' 创建成功！" \
        "接下来你可以：" \
        "" \
        "1. 开始第一个子功能开发：" \
        "   git-pr-flow start $epic_name/your-feature" \
        "" \
        "2. 查看Epic状态：" \
        "   git-pr-flow status" \
        "" \
        "3. 在VS Code中打开：" \
        "   git-pr-flow code $epic_name/your-feature"
}

# 验证Epic名称
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