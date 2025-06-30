#!/usr/bin/env bash

# Git PR Flow - init命令实现
# 初始化Epic开发环境，支持基分支智能检测和配置文件生成

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# init命令主函数
cmd_init() {
    local input_epic_name=""
    local input_base_branch=""
    local force_recreate=false
    local use_existing=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -yaml)
                force_recreate=true
                shift
                ;;
            -*)
                ui_error "未知选项: $1"
                ui_info "用法: gpf init <epic-name> [base-branch] [-yaml]"
                ui_info "  -yaml  重新编辑yaml配置文件"
                ui_info "  无参数: 使用现有配置（非交互式模式）"
                return 1
                ;;
            *)
                if [[ -z "$input_epic_name" ]]; then
                    input_epic_name="$1"
                elif [[ -z "$input_base_branch" ]]; then
                    input_base_branch="$1"
                else
                    ui_error "过多参数: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    # 如果没有提供Epic名称，显示现有配置或提示输入
    if [[ -z "$input_epic_name" ]]; then
        # 检查并确保在项目根目录执行
        ensure_project_root_directory
        
        # 更新Git hooks到最新版本
        update_git_hooks
        
        if ! handle_init_interactive; then
            return 1
        fi
        return 0
    fi
    
    # 标准化Epic名称 (支持输入epic/user-auth或user-auth)
    local base_epic_name
    base_epic_name=$(get_base_epic_name "$input_epic_name")
    local epic_branch_name
    epic_branch_name=$(to_epic_branch_name "$base_epic_name")
    
    # 验证基础Epic名称 - 在执行任何操作之前先验证参数
    if ! is_valid_epic_name "$base_epic_name"; then
        ui_error "Epic名称格式错误: \"$base_epic_name\""
        echo
        echo "要求: 小写字母、数字、连字符组合"
        echo
        echo "✅ 正确示例:"
        echo "  auth              # 认证功能"
        echo "  user-profile      # 用户档案功能"  
        echo "  payment-system    # 支付系统功能"
        echo
        echo "❌ 错误示例:"
        echo "  Auth              # 包含大写字母"
        echo "  user_profile      # 使用下划线"
        echo "  payment.system    # 使用点号"
        echo
        echo "请重新输入: gpf init <正确格式的epic名称>"
        return 1
    fi
    
    # 参数验证通过后，执行环境准备操作
    # 检查并确保在项目根目录执行
    ensure_project_root_directory
    
    # 更新Git hooks到最新版本
    update_git_hooks
    
    # 检查是否已存在Epic配置
    if config_epic_exists "$base_epic_name"; then
        handle_existing_epic_config "$base_epic_name" "$force_recreate" "$use_existing" "$input_base_branch"
        return $?
    fi
    
    # 执行新Epic初始化
    init_new_epic "$base_epic_name" "$epic_branch_name" "$input_base_branch"
}

# 显示init命令用法帮助
show_init_usage_help() {
    ui_header "🎯 GPF Epic 初始化"
    echo
    echo "用法: gpf init <epic-name> [base-branch]"
    echo
    echo "参数说明:"
    echo "  <epic-name>   Epic名称，小写字母+数字+连字符，描述总功能"
    echo "  [base-branch] 基础分支 (可选)"
    echo
    echo "示例:"
    echo "  gpf init auth develop          # 创建认证Epic，基于develop分支"
    echo "  gpf init user-management       # 创建用户管理Epic，使用默认分支"
    echo "  gpf init payment-system main   # 创建支付系统Epic，基于main分支"
    echo
    echo "💡 提示:"
    echo "  - 如果不指定base-branch，将使用 ~/.gpf/config.yaml 中的 epic_base_branch 设置"
    echo "  - 首次使用请指定分支，或先配置默认分支设置"
    echo
}

# 交互式初始化处理
handle_init_interactive() {
    ui_header "Epic开发环境初始化"
    
    # 检查现有配置
    local current_epic
    current_epic=$(detect_current_epic)
    if [[ -n "$current_epic" ]] && config_epic_exists "$current_epic"; then
        ui_subheader "检测到已有Epic配置"
        config_epic_show "$current_epic"
        
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
                epic_name=$(config_epic_get "epic_name" "$current_epic")
                if ui_confirm "确定要重新配置Epic '$epic_name' 吗？"; then
                    init_new_epic "$epic_name" "$(normalize_epic_name "$epic_name")" "$(normalize_epic_name "$epic_name")"
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
        # 没有现有配置，检查是否为非交互式环境
        if is_non_interactive; then
            # 非交互式环境，显示用法说明并退出
            ui_info "未发现Epic配置，且处于非交互式环境"
            show_init_usage_help
            return 1
        fi
        
        # 交互式环境，提示创建新Epic
        ui_info "未发现Epic配置，开始新Epic创建流程"
        
        local epic_name
        local attempts=0
        local max_attempts=3
        
        while [[ $attempts -lt $max_attempts ]]; do
            epic_name=$(ui_input "Epic名称" "")
            if [[ -n "$epic_name" ]] && is_valid_epic_name "$epic_name"; then
                break
            else
                ui_error "请输入有效的Epic名称 (小写字母、数字、连字符)"
                ((attempts++))
                if [[ $attempts -eq $max_attempts ]]; then
                    ui_error "连续输入错误达到最大次数，退出初始化"
                    return 1
                fi
            fi
        done
        
        init_new_epic "$epic_name" "$(normalize_epic_name "$epic_name")"
        return $?
    fi
}

# 处理已存在的Epic配置
handle_existing_epic_config() {
    local new_epic_name="$1"
    local force_recreate="${2:-false}"
    local use_existing="${3:-false}"
    local input_base_branch="${4:-}"
    
    local existing_epic_name
    existing_epic_name=$(config_epic_get "epic_name" "$new_epic_name")
    
    if [[ "$new_epic_name" == "$existing_epic_name" ]]; then
        ui_info "Epic '$new_epic_name' 已经初始化"
        config_epic_show "$new_epic_name"
        
        # 处理非交互式模式
        if [[ "$force_recreate" == "true" ]]; then
            ui_info "使用 -yaml 参数，重新初始化Epic配置"
            init_new_epic "$new_epic_name" "epic/$new_epic_name" "$input_base_branch"
            return $?
        elif [[ ! -t 0 ]] || [[ "$TERM" == "dumb" ]] || [[ -n "${GPF_NON_INTERACTIVE:-}" ]]; then
            # 非交互式环境且无-yaml参数，使用现有配置并切换到Epic目录
            ui_info "非交互式环境，使用现有Epic配置"
            ui_info "如需重新配置，请使用: gpf init $new_epic_name [base-branch] -yaml"
            ui_info "或手动编辑配置文件后重新运行命令"
            
            # 切换到Epic工作目录
            local epic_worktree_path
            epic_worktree_path=$(config_epic_get "worktree_path" "$new_epic_name")
            if [[ -d "$epic_worktree_path" ]]; then
                ui_info "切换到Epic工作目录: $epic_worktree_path"
                cd "$epic_worktree_path" || {
                    ui_error "无法切换到Epic工作目录"
                    return 1
                }
            fi
            return 0
        else
            # 交互式环境，询问用户
            if ui_confirm "是否要重新初始化？"; then
                init_new_epic "$new_epic_name" "epic/$new_epic_name" "$input_base_branch"
                return $?
            else
                return 0
            fi
        fi
    else
        ui_warning "当前目录已有不同的Epic配置: $existing_epic_name"
        ui_info "要初始化的Epic: $new_epic_name"
        
        # 处理非交互式模式
        if [[ "$force_recreate" == "true" ]]; then
            ui_info "使用 -yaml 参数，替换现有Epic配置"
            init_new_epic "$new_epic_name" "epic/$new_epic_name" "$input_base_branch"
            return $?
        elif [[ ! -t 0 ]] || [[ "$TERM" == "dumb" ]] || [[ -n "${GPF_NON_INTERACTIVE:-}" ]]; then
            ui_error "非交互式环境下不能自动替换不同的Epic配置"
            ui_info "当前Epic: $existing_epic_name"
            ui_info "目标Epic: $new_epic_name"
            ui_info "请使用以下方式之一："
            ui_info "  1. 强制替换: gpf init $new_epic_name [base-branch] -yaml"
            ui_info "  2. 使用现有Epic: gpf init $existing_epic_name"
            ui_info "  3. 手动删除配置文件后重新初始化"
            return 1
        else
            # 交互式环境，询问用户
            if ui_confirm "是否要替换现有配置？"; then
                init_new_epic "$new_epic_name" "epic/$new_epic_name" "$input_base_branch"
                return $?
            else
                ui_info "保持现有Epic配置: $existing_epic_name"
                return 1
            fi
        fi
    fi
}

# 初始化新Epic
init_new_epic() {
    local base_epic_name="$1"
    local epic_branch_name="$2"
    local input_base_branch="$3"
    
    ui_loading "正在初始化Epic: $base_epic_name (分支: $epic_branch_name)"
    
    # 1. 获取Epic描述
    local description
    if [[ ! -t 0 ]]; then
        # 非交互式模式，使用默认描述
        description="$base_epic_name Epic功能开发"
        ui_info "使用默认描述: $description"
    else
        description=$(ui_input "Epic描述" "$base_epic_name Epic功能开发")
        if [[ -z "$description" ]]; then
            description="$base_epic_name Epic功能开发"
        fi
    fi
    
    # 2. 智能检测和选择基分支
    # 引入项目配置系统以获取智能基分支选择功能
    source "$(dirname "${BASH_SOURCE[0]}")/../utils/project-config.sh"
    
    local base_branch
    base_branch=$(get_epic_base_branch_interactive "$input_base_branch")
    
    if [[ -z "$base_branch" ]]; then
        ui_error "无法确定基分支"
        return 1
    fi
    
    # 验证基分支是否存在
    if ! git_branch_exists "$base_branch"; then
        ui_error "基分支不存在: $base_branch"
        return 1
    fi
    
    ui_info "使用基分支: $base_branch"
    
    # 3. 生成工作树路径 (使用统一路径管理)
    local worktree_base_path
    worktree_base_path=$(get_epic_worktree_absolute_path "$base_epic_name")
    
    # 4. 确认配置
    ui_subheader "配置确认"
    echo "  Epic名称: $base_epic_name"
    echo "  Epic分支: $epic_branch_name"
    echo "  描述: $description"
    echo "  基础分支: $base_branch"
    echo "  工作树路径: $worktree_base_path"
    echo
    
    if [[ -t 0 ]]; then
        if ! ui_confirm "确认创建Epic配置？"; then
            ui_info "取消Epic创建"
            return 1
        fi
    else
        ui_info "非交互式环境，自动确认创建Epic配置"
    fi
    
    # 5. 创建Epic分支
    ui_loading "创建Epic分支: $epic_branch_name"
    if ! git_create_epic_branch "$epic_branch_name" "$base_branch"; then
        ui_error "Epic分支创建失败"
        return 1
    fi
    
    # 6. 创建Epic工作树（必须在创建配置文件之前，确保当前不在Epic分支上）
    ui_loading "创建Epic工作树: $worktree_base_path"
    ensure_dir "$(dirname "$worktree_base_path")"
    
    # 检查并清理可能存在的目录
    if [[ -d "$worktree_base_path" ]]; then
        ui_warning "工作树目录已存在，清理中: $worktree_base_path"
        rm -rf "$worktree_base_path"
    fi
    
    # 确保当前不在Epic分支上（避免git worktree add冲突）
    local current_branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" == "$epic_branch_name" ]]; then
        ui_info "切换到基础分支以创建工作树"
        git checkout "$base_branch"
    fi
    
    # 创建实际的git worktree
    if ! git worktree add "$worktree_base_path" "$epic_branch_name"; then
        ui_error "Epic工作树创建失败: $worktree_base_path"
        return 1
    fi
    
    # 7. 注册Epic到项目配置（替代创建YAML文件）
    # 引入项目配置系统
    source "$(dirname "${BASH_SOURCE[0]}")/../utils/project-config.sh"
    
    # 确保项目配置已初始化
    if ! gpf_project_config_exists; then
        # 如果项目配置不存在，用用户指定的base_branch作为epic_base_branch来初始化
        init_project_config "$base_branch"
    fi
    
    # Epic 信息通过 Git 分支管理，不需要额外存储
    
    ui_success "Epic工作树创建成功: $worktree_base_path"
    
    # 8. 自动切换到Epic工作目录
    ui_info "切换到Epic工作目录..."
    cd "$worktree_base_path" || {
        ui_error "无法切换到Epic目录: $worktree_base_path"
        return 1
    }
    ui_success "已切换到Epic工作目录: $worktree_base_path"
    
    # 9. 自动生成Epic路线图
    ui_loading "生成Epic路线图文档..."
    
    # 加载路线图生成工具
    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../utils/auto-roadmap.sh" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/../utils/auto-roadmap.sh"
        
        local roadmap_file
        roadmap_file=$(generate_epic_roadmap "$base_epic_name" "$description" "$base_branch")
        
        if [[ -f "$roadmap_file" ]]; then
            ui_success "Epic路线图已创建: $roadmap_file"
        else
            ui_warning "路线图创建失败，请手动创建"
        fi
    else
        ui_warning "路线图生成工具未找到，跳过路线图创建"
    fi
    
    # 10. 显示后续步骤
    show_next_steps "$base_epic_name"
    
    ui_success "Epic '$base_epic_name' 初始化完成！"
    ui_info "Epic分支: $epic_branch_name"
    ui_info "工作树路径: $worktree_base_path"
    return 0
}

# 智能基分支选择
select_base_branch() {
    ui_subheader "基分支选择"
    
    # 非交互式环境：使用智能默认值
    if [[ ! -t 0 ]]; then
        ui_error "非交互式环境需要指定基分支参数"
        ui_info "用法: gpf init <epic-name> <base-branch>"
        ui_info "示例: gpf init ai-friendly develop"
        return 1
    fi
    
    # 交互式环境：检测项目中现有的重要分支
    local detected_branches=()
    local branch_descriptions=()
    
    # 检测常见的主分支（按优先级排序）
    if git_branch_exists "develop"; then
        detected_branches+=("develop")
        branch_descriptions+=("develop (GitFlow开发分支) ⭐ 推荐")
    fi
    
    if git_branch_exists "main"; then
        detected_branches+=("main")
        branch_descriptions+=("main (GitHub主分支) ⭐ 推荐")
    fi
    
    if git_branch_exists "master"; then
        detected_branches+=("master")
        branch_descriptions+=("master (传统主分支)")
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
    for i in "${!detected_branches[@]}"; do
        echo "  $((i+1)). ${branch_descriptions[$i]}"
    done
    echo
    
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


# 显示详细配置信息
show_detailed_config() {
    ui_header "Epic配置详情"
    
    local current_epic
    current_epic=$(detect_current_epic)
    if [[ -z "$current_epic" ]]; then
        ui_error "无法检测当前Epic"
        return 1
    fi
    
    if ! config_epic_validate "$current_epic"; then
        return 1
    fi
    
    local epic_name description base_branch worktree_path created_at config_version
    epic_name=$(config_epic_get "epic_name" "$current_epic")
    description=$(config_epic_get "description" "$current_epic")
    base_branch=$(config_epic_get "base_branch" "$current_epic")
    worktree_path=$(config_epic_get "worktree_path" "$current_epic")
    created_at=$(config_epic_get "created_at" "$current_epic")
    config_version=$(config_epic_get "config_version" "$current_epic")
    
    echo "📋 基本信息:"
    echo "  Epic名称: $epic_name"
    echo "  描述: $description"
    echo "  基础分支: $base_branch"
    echo "  工作树路径: $worktree_path"
    echo "  配置版本: $config_version"
    echo "  创建时间: $created_at"
    echo
    
    echo "🔧 自动化设置:"
    echo "  自动分支切换: $(config_epic_get "auto_switch_branch" "$current_epic")"
    echo "  自动同步: $(config_epic_get "auto_sync" "$current_epic")"
    echo "  自动清理: $(config_epic_get "auto_cleanup" "$current_epic")"
    echo
    
    echo "🔄 工作流设置:"
    echo "  工作流类型: $(config_epic_get "workflow_type" "$current_epic")"
    echo "  PR策略: $(config_epic_get "pr_strategy" "$current_epic")"
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
    
    ui_success_box "$epic_name 创建成功！" \
        "Epic名称: $epic_name" \
        "Worktree目录名: epic--$epic_name" \
        "Git分支名: epic/$epic_name" \
        "已在docs/epic/目录下创建了 $epic_name-roadmap.md" \
        "" \
        "请先完成这个文档，说明这个epic将要负责解决什么问题，" \
        "分哪些子功能，每个子功能验收标准是什么，" \
        "之后commit，然后执行：" \
        "" \
        "gpf start $epic_name/功能名 创建你规划的第一个子功能，并开始开发"
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

# 更新Git hooks到最新版本
update_git_hooks() {
    # 确保hooks目录存在
    local hooks_dir="$HOME/.gpf/hooks"
    mkdir -p "$hooks_dir"
    
    # 创建优化后的pre-commit hook
    cat > "$hooks_dir/pre-commit" << 'EOF'
#!/usr/bin/env bash
# GPF Pre-commit Hook - 全局Git PR Flow工作流保护
# 支持通过环境变量或提交消息强制提交

# 检查强制提交标志
check_force_commit() {
    # 方法1: 检查环境变量
    if [[ "${GPF_FORCE_COMMIT:-}" == "1" ]]; then
        return 0
    fi
    
    # 方法2: 检查提交消息中的强制标志
    if [[ -n "${1:-}" ]] && grep -q "GPF_FORCE_COMMIT" "$1" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# 检查是否只提交允许的文件
check_epic_allowlist() {
    local current_branch="$1"
    
    # 获取此次提交涉及的文件
    local staged_files
    staged_files=$(git diff --cached --name-only)
    
    # 检查是否所有文件都在允许列表中
    local disallowed_files=""
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            # 允许的文件类型：docs/epic/目录下的.md文件
            if [[ "$file" == docs/epic/*.md ]]; then
                continue  # 允许
            fi
            # 其他文件不允许
            disallowed_files="$disallowed_files $file"
        fi
    done <<< "$staged_files"
    
    if [[ -n "$disallowed_files" ]]; then
        echo ""
        echo "🚫 GPF工作流保护: Epic分支只允许提交roadmap文档"
        echo ""
        echo "💡 Epic分支 ($current_branch) 允许提交的文件："
        echo "  ✅ docs/epic/*.md (Epic路线图文档)"
        echo ""
        echo "❌ 不允许提交的文件："
        for file in $disallowed_files; do
            echo "  - $file"
        done
        echo ""
        echo "建议操作:"
        local epic_name="${current_branch#epic/}"
        echo "  1. 撤销当前提交: git reset HEAD"
        echo "  2. 只提交roadmap文档: git add docs/epic/*.md && git commit"
        echo "  3. 或创建功能分支开发: gpf start $epic_name/implementation"
        return 1
    fi
    
    # 所有文件都在允许列表中
    return 0
}

# 显示强制提交选项
show_force_options() {
    local context="$1"
    echo ""
    echo "🔧 如果你需要强制提交(不推荐)，可以使用:"
    echo "  方法1: GPF_FORCE_COMMIT=1 git commit -m \"your message\""
    echo "  方法2: git commit -m \"your message GPF_FORCE_COMMIT\""
    echo ""
    echo "⚠️  强制提交会跳过GPF工作流保护，请谨慎使用！"
    echo ""
}

# 检查是否在GPF项目中
if [[ -f "bin/git-pr-flow" ]] || [[ -f ".git-pr-flow.yaml" ]] || git rev-parse --show-toplevel 2>/dev/null | xargs -I {} test -f "{}/bin/git-pr-flow"; then
    # 在GPF项目中，应用严格工作流检查
    current_branch=$(git branch --show-current 2>/dev/null)
    
    # 获取提交消息文件路径（如果有的话）
    commit_msg_file="$1"
    
    # 检查是否强制提交
    if check_force_commit "$commit_msg_file"; then
        echo "⚠️  GPF工作流保护已被强制跳过 (GPF_FORCE_COMMIT)"
        echo "📝 提交分支: $current_branch"
        exit 0
    fi
    
    # 检查Epic分支直接开发
    if [[ "$current_branch" == epic/* ]]; then
        # 检查是否只提交允许的文件
        if check_epic_allowlist "$current_branch"; then
            echo "✅ Epic分支roadmap文档提交已允许"
            exit 0
        fi
        
        # 如果有不允许的文件，显示传统的引导信息
        echo "建议操作:"
        local epic_name="${current_branch#epic/}"
        echo "  1. 创建功能分支进行开发:"
        echo "     gpf start $epic_name/implementation"
        echo ""
        echo "  2. 在功能分支上完成开发后:"
        echo "     gpf ready    # 检查就绪状态"
        echo "     gpf pr       # 创建PR到Epic分支"
        echo ""
        
        # 交互式环境提供用户选择
        if [[ -t 0 && -t 1 ]]; then
            echo "🔄 要创建功能分支吗? (y/n)"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "请输入功能名称 (例如: implementation, fix-bug, add-feature):"
                read -r feature_name
                if [[ -n "$feature_name" ]]; then
                    echo "💡 请运行: gpf start $epic_name/$feature_name"
                fi
            fi
        fi
        
        show_force_options "epic"
        exit 1
    fi
    
    # 检查主分支直接开发
    if [[ "$current_branch" == "develop" || "$current_branch" == "main" || "$current_branch" == "master" ]]; then
        echo ""
        echo "🚫 GPF工作流保护: 禁止在主分支上直接提交"
        echo ""
        echo "建议操作:"
        echo "  1. 创建Epic: gpf init <epic-name>"
        echo "  2. 创建功能分支: gpf start <epic-name>/<feature-name>"
        
        show_force_options "main"
        exit 1
    fi
fi

# 非GPF项目或在允许的分支上，正常通过
exit 0
EOF
    
    # 设置hooks为可执行
    chmod +x "$hooks_dir/pre-commit"
    
    # 配置Git使用全局hooks目录
    git config --global core.hookspath "$hooks_dir" 2>/dev/null
}