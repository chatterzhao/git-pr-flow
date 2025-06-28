#!/usr/bin/env bash

# Git PR Flow - start命令实现
# 开始子功能开发，含自动分支切换和依赖关系检测

# start命令主函数
cmd_start() {
    local input_feature_name="$1"
    
    # 检查Epic配置
    local current_epic
    current_epic=$(detect_current_epic)
    if [[ -z "$current_epic" ]] || ! config_epic_exists "$current_epic"; then
        ui_error "未找到Epic配置文件"
        ui_info "请先运行: git-pr-flow init <epic-name>"
        return 1
    fi
    
    if ! config_epic_validate "$current_epic"; then
        ui_error "Epic配置文件无效"
        return 1
    fi
    
    # 如果没有提供功能名称，显示交互式选择
    if [[ -z "$input_feature_name" ]]; then
        if ! handle_start_interactive; then
            return 1
        fi
        return 0
    fi
    
    # 标准化功能名称 (支持输入 epic/user-auth/login 或 user-auth/login)
    local normalized_feature_name
    normalized_feature_name=$(normalize_feature_name "$input_feature_name")
    
    # 验证功能名称格式
    if ! is_valid_feature_name "$normalized_feature_name"; then
        ui_error "无效的功能名称: $normalized_feature_name"
        ui_info "功能名称格式: epic-name/feature-name，如: auth/login, user-profile/avatar"
        return 1
    fi
    
    # 执行功能开发启动
    start_feature_development "$normalized_feature_name"
}

# 交互式启动处理
handle_start_interactive() {
    local current_epic epic_name
    current_epic=$(detect_current_epic)
    epic_name=$(config_epic_get "epic_name" "$current_epic")
    
    ui_header "开始子功能开发"
    ui_info "当前Epic: $epic_name ($(config_epic_get "description" "$current_epic"))"
    
    # 列出现有的子功能分支
    local existing_features=()
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -n "$feature_branches" ]]; then
        ui_subheader "现有子功能分支"
        
        while IFS= read -r branch; do
            existing_features+=("$branch")
            local worktree_path status_icon
            worktree_path=$(branch_to_worktree_path "$branch")
            
            if [[ -d "$worktree_path" ]]; then
                status_icon="🏠"
            else
                status_icon="📋"
            fi
            
            echo "  $status_icon $branch"
        done <<< "$feature_branches"
        echo
    fi
    
    # 选择操作
    local options=(
        "创建新的子功能"
        "切换到现有子功能"
        "查看Epic状态"
        "取消操作"
    )
    
    local choice
    choice=$(ui_select_menu "选择操作" "${options[@]}")
    
    case $choice in
        0) # 创建新功能
            create_new_feature_interactive "$epic_name"
            ;;
        1) # 切换到现有功能
            if [[ ${#existing_features[@]} -eq 0 ]]; then
                ui_warning "没有现有的子功能分支"
                return 1
            fi
            switch_to_existing_feature "${existing_features[@]}"
            ;;
        2) # 查看Epic状态
            show_epic_status
            ;;
        3) # 取消操作
            ui_info "取消操作"
            return 1
            ;;
    esac
}

# 交互式创建新功能
create_new_feature_interactive() {
    local epic_name="$1"
    
    ui_subheader "创建新子功能"
    
    local feature_name
    while true; do
        feature_name=$(ui_input "子功能名称" "")
        if [[ -n "$feature_name" ]]; then
            local full_feature_name="$epic_name/$feature_name"
            if is_valid_feature_name "$full_feature_name"; then
                if ! git_branch_exists "$full_feature_name"; then
                    break
                else
                    ui_error "功能分支已存在: $full_feature_name"
                fi
            else
                ui_error "无效的功能名称格式"
            fi
        fi
    done
    
    start_feature_development "$epic_name/$feature_name"
}

# 切换到现有功能
switch_to_existing_feature() {
    local features=("$@")
    
    ui_subheader "选择要切换的子功能"
    
    local choice
    choice=$(ui_select_menu "选择子功能" "${features[@]}")
    
    local selected_feature="${features[$choice]}"
    start_feature_development "$selected_feature"
}

# 启动功能开发
start_feature_development() {
    local feature_name="$1"
    local current_epic epic_name base_branch
    
    current_epic=$(detect_current_epic)
    epic_name=$(config_epic_get "epic_name" "$current_epic")
    base_branch=$(config_epic_get "base_branch" "$current_epic")
    
    ui_loading "启动功能开发: $feature_name"
    
    # 解析Epic名称和功能名称
    local parsed_epic parsed_feature
    if ! parse_feature_name "$feature_name" parsed_epic parsed_feature; then
        ui_error "无法解析功能名称: $feature_name"
        return 1
    fi
    
    # 验证Epic匹配
    if [[ "$parsed_epic" != "$epic_name" ]]; then
        ui_error "功能Epic不匹配: $parsed_epic (期望: $epic_name)"
        return 1
    fi
    
    # 生成工作树路径
    local worktree_path
    worktree_path=$(branch_to_worktree_path "$feature_name")
    
    ui_subheader "功能开发配置"
    echo "  功能名称: $feature_name"
    echo "  Epic: $epic_name"
    echo "  子功能: $parsed_feature"
    echo "  工作树路径: $worktree_path"
    
    # 检查依赖关系
    local dependencies
    if ! dependencies=$(detect_feature_dependencies "$feature_name"); then
        ui_error "依赖关系检测失败"
        return 1
    fi
    
    if [[ -n "$dependencies" ]]; then
        echo "  检测到依赖: $dependencies"
    else
        echo "  依赖关系: 无 (基础功能)"
    fi
    echo
    
    # 确认创建
    if [[ -t 0 ]]; then
        if ! ui_confirm "确认启动功能开发？"; then
            ui_info "取消功能开发启动"
            return 1
        fi
    else
        ui_info "非交互式环境，自动确认启动功能开发"
    fi
    
    # 执行核心逻辑
    if ! execute_feature_start "$feature_name" "$worktree_path" "$dependencies"; then
        return 1
    fi
    
    # 🔄 自动分支切换 - 核心功能
    perform_auto_branch_switch "$feature_name"
    
    # 显示成功信息和后续步骤
    show_feature_start_success "$feature_name" "$worktree_path"
    
    return 0
}

# 执行功能启动核心逻辑
execute_feature_start() {
    local feature_name="$1"
    local worktree_path="$2"
    local dependencies="$3"
    
    local current_epic base_branch
    current_epic=$(detect_current_epic)
    base_branch=$(config_epic_get "base_branch" "$current_epic")
    
    # 确定基础分支
    local base_for_branch="$base_branch"
    if [[ -n "$dependencies" ]]; then
        # 如果有依赖，基于依赖分支创建
        base_for_branch="$dependencies"
        ui_info "基于依赖分支创建: $dependencies"
    else
        ui_info "基于基础分支创建: $base_branch"
    fi
    
    # 检查工作树是否已存在
    if [[ -d "$worktree_path" ]]; then
        ui_info "工作树已存在，切换到现有环境"
        
        # 验证工作树状态
        if git_worktree_exists "$worktree_path"; then
            ui_success "切换到现有工作树: $worktree_path"
            return 0
        else
            ui_warning "工作树目录存在但未在Git中注册，尝试修复"
            # 可以在这里添加修复逻辑
        fi
    fi
    
    # 创建工作树和分支
    ui_loading "创建工作树和分支"
    
    # 生成功能分支名称（不包含epic/前缀）
    local feature_branch_name
    if [[ "$feature_name" == epic/* ]]; then
        feature_branch_name=$(echo "$feature_name" | sed 's|^epic/||')
    else
        feature_branch_name="$feature_name"
    fi
    
    if ! git_create_worktree "$worktree_path" "$feature_branch_name" "$base_for_branch"; then
        ui_error "创建工作树失败"
        return 1
    fi
    
    ui_success "工作树创建成功: $worktree_path"
    return 0
}

# 自动分支切换 - 核心功能实现
perform_auto_branch_switch() {
    local feature_name="$1"
    
    # 检查是否启用自动分支切换
    local current_epic auto_switch
    current_epic=$(detect_current_epic)
    auto_switch=$(config_epic_get "auto_switch_branch" "$current_epic")
    if [[ "$auto_switch" != "true" ]]; then
        ui_info "自动分支切换已禁用"
        return 0
    fi
    
    ui_loading "🔄 执行自动分支切换"
    
    # 获取当前工作目录，稍后返回
    local original_dir
    original_dir=$(pwd)
    
    # 切换到主仓库目录执行分支切换
    cd "$(git rev-parse --show-toplevel)" || {
        ui_error "无法找到Git仓库根目录"
        return 1
    }
    
    # 计算实际的功能分支名称（去除epic/前缀）
    local target_branch
    if [[ "$feature_name" == epic/* ]]; then
        target_branch=$(echo "$feature_name" | sed 's|^epic/||')
    else
        target_branch="$feature_name"
    fi
    
    # 执行自动分支切换
    if git_auto_switch_branch "$target_branch"; then
        ui_success "✅ 自动分支切换成功"
        ui_info "💡 VS Code现在可以显示 '$target_branch' 的文件变更"
        ui_info "💡 主仓库Git面板将显示当前功能的修改状态"
    else
        ui_warning "⚠️ 自动分支切换失败或跳过"
        ui_info "💡 可能原因：分支被占用、工作目录不干净或分支不存在"
        ui_info "💡 你仍然可以在worktree中正常开发"
    fi
    
    # 返回原始目录
    cd "$original_dir" || true
    
    return 0
}

# 显示功能启动成功信息
show_feature_start_success() {
    local feature_name="$1"
    local worktree_path="$2"
    
    ui_success_box "功能开发环境就绪！" \
        "功能: $feature_name" \
        "工作树: $worktree_path" \
        "" \
        "下一步操作：" \
        "1. 进入开发目录: cd $worktree_path" \
        "2. 开始正常开发和提交" \
        "3. 在VS Code中打开: git-pr-flow code $feature_name" \
        "4. 查看状态: git-pr-flow status"
    
    # VS Code集成提示
    echo "💻 VS Code集成："
    echo "  git-pr-flow code $feature_name  # 在VS Code中打开"
    echo "  git-pr-flow workspace           # 生成多Epic工作区"
    echo
    
    # 自动分支切换状态
    local current_main_branch target_branch
    current_main_branch=$(cd "$(git rev-parse --show-toplevel)" && git_current_branch)
    if [[ "$feature_name" == epic/* ]]; then
        target_branch=$(echo "$feature_name" | sed 's|^epic/||')
    else
        target_branch="$feature_name"
    fi
    
    if [[ "$current_main_branch" == "$target_branch" ]]; then
        echo "🔄 自动分支切换状态: ✅ 成功"
        echo "   主仓库当前分支: $current_main_branch"
        echo "   VS Code Git面板: 可显示当前功能的文件变更"
    else
        echo "🔄 自动分支切换状态: ⚠️ 未切换"
        echo "   主仓库当前分支: $current_main_branch"
        echo "   建议: 在worktree目录中使用VS Code"
    fi
}

# 依赖关系检测
detect_feature_dependencies() {
    local feature_name="$1"
    local current_epic epic_name
    current_epic=$(detect_current_epic)
    epic_name=$(config_epic_get "epic_name" "$current_epic")
    
    # 获取同Epic下的所有分支
    local epic_branches
    epic_branches=$(git_list_branches | grep "^$epic_name/" | grep -v "^$feature_name$" || true)
    
    if [[ -z "$epic_branches" ]]; then
        # 没有其他分支，返回空（基于基础分支）
        return 0
    fi
    
    # 简单的依赖推荐逻辑
    # 实际项目中可以基于文件变更、提交历史等进行智能分析
    
    {
        ui_subheader "依赖关系检测"
        echo "  检测到同Epic下的其他分支："
        
        local branches_array=()
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                branches_array+=("$branch")
                echo "    📋 $branch"
            fi
        done <<< "$epic_branches"
        
        if [[ ${#branches_array[@]} -eq 0 ]]; then
            echo "    (无)"
        fi
        
        echo
    } >&2
    
    # 依赖关系选择 (支持非交互式环境)
    if [[ ! -t 0 ]]; then
        # 非交互式环境：自动选择无依赖
        ui_info "非交互式环境，自动选择: 无依赖 (基于基础分支)" >&2
        return 0
    fi
    
    # 交互式环境：提供选择菜单
    local dep_options=(
        "无依赖 (基于基础分支)"
        "智能推荐 (基于最新分支)"
    )
    
    # 添加具体分支选项
    for branch in "${branches_array[@]}"; do
        dep_options+=("依赖 $branch")
    done
    
    local choice
    choice=$(ui_select_menu "选择依赖关系" "${dep_options[@]}")
    
    case $choice in
        0) # 无依赖
            return 0
            ;;
        1) # 智能推荐
            if [[ ${#branches_array[@]} -gt 0 ]]; then
                # 返回最新的分支作为依赖
                echo "${branches_array[0]}"
            fi
            ;;
        *) # 具体分支
            local branch_index=$((choice - 2))
            if [[ $branch_index -ge 0 && $branch_index -lt ${#branches_array[@]} ]]; then
                echo "${branches_array[$branch_index]}"
            fi
            ;;
    esac
}

# 显示Epic状态
show_epic_status() {
    local current_epic epic_name
    current_epic=$(detect_current_epic)
    epic_name=$(config_epic_get "epic_name" "$current_epic")
    
    ui_header "Epic状态: $epic_name"
    
    # 基本信息
    config_epic_show "$current_epic"
    
    # 分支状态
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -n "$feature_branches" ]]; then
        ui_subheader "子功能分支状态"
        
        while IFS= read -r branch; do
            local worktree_path status commits_info
            worktree_path=$(branch_to_worktree_path "$branch")
            
            if [[ -d "$worktree_path" ]]; then
                status="🏠 活跃"
            else
                status="📋 分支"
            fi
            
            # 获取提交信息
            commits_info=$(git log --oneline "$branch" 2>/dev/null | wc -l | tr -d ' ')
            
            echo "  $status $branch ($commits_info 提交)"
            if [[ -d "$worktree_path" ]]; then
                echo "    └─ 工作树: $worktree_path"
            fi
        done <<< "$feature_branches"
    else
        ui_info "暂无子功能分支"
    fi
}

# 验证功能名称格式
is_valid_feature_name() {
    local feature_name="$1"
    
    # 支持两种格式：epic/user-auth/login 或 user-auth/login
    local epic_part feature_part
    
    if [[ "$feature_name" == epic/* ]]; then
        # epic/user-auth/login 格式
        epic_part=$(echo "$feature_name" | sed 's|^epic/\([^/]*\)/.*|\1|')
        feature_part=$(echo "$feature_name" | sed 's|^epic/[^/]*/\(.*\)|\1|')
    elif [[ "$feature_name" == */* ]]; then
        # user-auth/login 格式
        epic_part=$(echo "$feature_name" | sed 's|^\([^/]*\)/.*|\1|')
        feature_part=$(echo "$feature_name" | sed 's|^[^/]*/\(.*\)|\1|')
    else
        return 1
    fi
    
    # 验证Epic部分
    if [[ -z "$epic_part" ]] || ! is_valid_epic_name "$epic_part"; then
        return 1
    fi
    
    # 验证功能部分
    if [[ -z "$feature_part" ]]; then
        return 1
    fi
    
    # 功能名称格式检查：只允许小写字母、数字、连字符
    if [[ "$feature_part" =~ [^a-z0-9-] ]]; then
        return 1
    fi
    
    # 不能以连字符开头或结尾
    if [[ "$feature_part" =~ ^- ]] || [[ "$feature_part" =~ -$ ]]; then
        return 1
    fi
    
    return 0
}

# 解析功能名称
parse_feature_name() {
    local feature_name="$1"
    local epic_var="$2"
    local feature_var="$3"
    
    # 支持 epic/user-auth/login 格式
    if [[ "$feature_name" == epic/* ]]; then
        local epic_part
        local feature_part
        epic_part=$(echo "$feature_name" | sed 's|^epic/\([^/]*\)/.*|\1|')
        feature_part=$(echo "$feature_name" | sed 's|^epic/[^/]*/\(.*\)|\1|')
        
        if [[ -n "$epic_part" && -n "$feature_part" ]]; then
            eval "$epic_var=\"$epic_part\""
            eval "$feature_var=\"$feature_part\""
            return 0
        fi
    fi
    
    # 兼容旧格式 user-auth/login (自动转换)
    if [[ "$feature_name" == */* && "$feature_name" != epic/* ]]; then
        local epic_part
        local feature_part
        epic_part=$(echo "$feature_name" | sed 's|^\([^/]*\)/.*|\1|')
        feature_part=$(echo "$feature_name" | sed 's|^[^/]*/\(.*\)|\1|')
        
        if [[ -n "$epic_part" && -n "$feature_part" ]]; then
            eval "$epic_var=\"$epic_part\""
            eval "$feature_var=\"$feature_part\""
            return 0
        fi
    fi
    
    return 1
}