#!/usr/bin/env bash

# Git PR Flow - sync命令实现
# 智能同步依赖关系，处理Epic内分支间的同步和合并

# 引入环境检测工具
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../utils/environment.sh"

# sync命令主函数
cmd_sync() {
    local scope=""
    local target=""
    local non_interactive="false"
    local auto_confirm="false"
    local sync_strategy=""
    local conflict_action=""  # 明确的冲突处理动作
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive|-n)
                non_interactive="true"
                set_non_interactive_mode
                shift
                ;;
            --auto-confirm|-y)
                auto_confirm="true"
                export GPF_AUTO_CONFIRM="true"
                shift
                ;;
            --strategy)
                if [[ -n "$2" && "$2" != -* ]]; then
                    sync_strategy="$2"
                    export GPF_SYNC_STRATEGY="$sync_strategy"
                    shift 2
                else
                    ui_error "--strategy 选项需要指定策略值 (deps|base|all)"
                    return 1
                fi
                ;;
            --abort)
                conflict_action="abort"
                shift
                ;;
            --skip)
                conflict_action="skip"
                shift
                ;;
            --accept-source)
                conflict_action="accept-source"
                shift
                ;;
            --accept-target)
                conflict_action="accept-target"
                shift
                ;;
            --help|-h)
                show_sync_help
                return 0
                ;;
            -*)
                ui_error "未知选项: $1"
                show_sync_help
                return 1
                ;;
            *)
                if [[ -z "$scope" ]]; then
                    scope="$1"
                elif [[ -z "$target" ]]; then
                    target="$1"
                else
                    ui_error "过多的参数: $1"
                    show_sync_help
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    # 设置默认值
    scope="${scope:-deps}"
    
    # 记录操作日志（如果需要）
    if [[ "$non_interactive" == "true" ]]; then
        log_non_interactive_operation "sync" "scope=$scope target=$target conflict_action=$conflict_action"
    fi
    
    # 检查Epic配置
    if ! config_epic_exists; then
        ui_error "未找到Epic配置文件"
        ui_info "请先运行: gpf init <epic-name>"
        return 1
    fi
    
    # 获取当前epic名称用于验证
    local epic_name
    epic_name=$(detect_current_epic)
    if [[ -z "$epic_name" ]]; then
        ui_error "无法检测当前Epic名称"
        return 1
    fi

    if ! config_epic_validate "$epic_name"; then
        ui_error "Epic配置文件无效"
        return 1
    fi
    
    case "$scope" in
        "deps"|"dependencies")
            sync_dependencies "$target"
            ;;
        "base")
            sync_with_base_branch "$target"
            ;;
        "all")
            sync_all_branches
            ;;
        "feature")
            if [[ -z "$target" ]]; then
                ui_error "同步特定功能需要指定功能名称"
                ui_info "用法: git-pr-flow sync feature <feature-name>"
                return 1
            fi
            sync_specific_feature "$target"
            ;;
        *)
            ui_error "无效的同步范围: $scope"
            ui_info "支持的范围: deps, base, all, feature"
            ui_info "用法示例:"
            ui_info "  git-pr-flow sync deps           # 同步当前功能的依赖"
            ui_info "  git-pr-flow sync base           # 同步基础分支变更"
            ui_info "  git-pr-flow sync all            # 同步整个Epic"
            ui_info "  git-pr-flow sync feature auth/login # 同步特定功能"
            return 1
            ;;
    esac
}

# 同步依赖关系
sync_dependencies() {
    local target_feature="$1"
    local current_branch epic_name
    
    current_branch=$(git_current_branch)
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "依赖关系同步"
    
    # 确定要同步的功能
    local feature_to_sync
    if [[ -n "$target_feature" ]]; then
        feature_to_sync="$target_feature"
        ui_info "同步指定功能: $feature_to_sync"
    else
        # 自动检测当前功能
        if [[ "$current_branch" =~ ^$epic_name/ ]]; then
            feature_to_sync="$current_branch"
            ui_info "同步当前功能: $feature_to_sync"
        else
            ui_warning "当前不在Epic功能分支中"
            select_feature_for_sync "$epic_name"
            return $?
        fi
    fi
    
    # 验证功能存在
    if ! git_branch_exists "$feature_to_sync"; then
        ui_error "功能分支不存在: $feature_to_sync"
        return 1
    fi
    
    # 检测依赖关系
    local dependencies
    dependencies=$(detect_sync_dependencies "$feature_to_sync")
    
    if [[ -z "$dependencies" ]]; then
        ui_info "📋 功能 '$feature_to_sync' 没有依赖，检查基础分支同步"
        sync_feature_with_base "$feature_to_sync"
        return $?
    fi
    
    ui_subheader "检测到依赖关系"
    echo "  🔗 功能: $feature_to_sync"
    echo "  🔗 依赖: $dependencies"
    echo
    
    if ! ui_confirm "确认同步依赖关系？"; then
        ui_info "取消同步操作"
        return 1
    fi
    
    # 执行依赖同步
    execute_dependency_sync "$feature_to_sync" "$dependencies"
}

# 检测同步依赖关系
detect_sync_dependencies() {
    local feature_branch="$1"
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 获取同Epic下的所有其他分支
    local other_branches
    other_branches=$(git_list_branches | grep "^$epic_name/" | grep -v "^$feature_branch$" || true)
    
    if [[ -z "$other_branches" ]]; then
        return 0
    fi
    
    # 简单的依赖检测逻辑
    # 实际项目中可以基于提交历史、文件变更等进行更智能的分析
    
    ui_subheader "依赖关系分析"
    echo "  检测同Epic下的其他分支："
    
    local dependency_candidates=()
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            dependency_candidates+=("$branch")
            echo "    📋 $branch"
        fi
    done <<< "$other_branches"
    
    if [[ ${#dependency_candidates[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo
    
    # 提供依赖选择
    local dep_options=(
        "无依赖 (仅同步基础分支)"
        "智能检测 (基于Git历史)"
    )
    
    # 添加具体分支选项
    for branch in "${dependency_candidates[@]}"; do
        dep_options+=(\"依赖 $branch\")
    done
    
    local choice
    choice=$(ui_select_menu "选择依赖策略" "${dep_options[@]}")
    
    case $choice in
        0) # 无依赖
            return 0
            ;;
        1) # 智能检测
            # 返回最可能的依赖（简单实现：按时间排序的第一个）
            if [[ ${#dependency_candidates[@]} -gt 0 ]]; then
                echo "${dependency_candidates[0]}"
            fi
            ;;
        *) # 具体分支
            local branch_index=$((choice - 2))
            if [[ $branch_index -ge 0 && $branch_index -lt ${#dependency_candidates[@]} ]]; then
                echo "${dependency_candidates[$branch_index]}"
            fi
            ;;
    esac
}

# 执行依赖同步
execute_dependency_sync() {
    local feature_branch="$1"
    local dependency_branch="$2"
    
    ui_loading "执行依赖同步: $feature_branch <- $dependency_branch"
    
    # 切换到功能分支的工作树
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$feature_branch")
    
    if [[ ! -d "$worktree_path" ]]; then
        ui_error "功能分支工作树不存在: $worktree_path"
        ui_info "请先运行: gpf start $feature_branch"
        return 1
    fi
    
    # 在工作树中执行同步
    local original_dir
    original_dir=$(pwd)
    
    cd "$worktree_path" || {
        ui_error "无法进入工作树: $worktree_path"
        return 1
    }
    
    # 检查工作目录状态
    if ! git_is_clean; then
        ui_warning "工作目录不干净，请先提交或暂存更改"
        ui_info "当前状态: $(git_status_summary)"
        cd "$original_dir" || true
        return 1
    fi
    
    # 执行合并
    ui_info "🔄 从 '$dependency_branch' 合并变更到 '$feature_branch'"
    
    if git merge --no-ff "$dependency_branch" --message "feat: 同步依赖分支 $dependency_branch 的变更" >/dev/null 2>&1; then
        ui_success "✅ 依赖同步成功"
        
        # 显示同步摘要
        show_sync_summary "$feature_branch" "$dependency_branch"
    else
        ui_error "❌ 依赖同步失败，可能存在冲突"
        
        # 处理冲突
        handle_merge_conflict "$feature_branch" "$dependency_branch" "$conflict_action"
    fi
    
    cd "$original_dir" || true
}

# 与基础分支同步
sync_with_base_branch() {
    local target_feature="$1"
    local epic_name base_branch
    
    epic_name=$(config_epic_get "epic_name")
    base_branch=$(config_epic_get "base_branch")
    
    ui_header "基础分支同步"
    
    # 确定要同步的功能
    local feature_to_sync
    if [[ -n "$target_feature" ]]; then
        feature_to_sync="$target_feature"
    else
        select_feature_for_sync "$epic_name"
        return $?
    fi
    
    if [[ -z "$feature_to_sync" ]]; then
        return 1
    fi
    
    sync_feature_with_base "$feature_to_sync"
}

# 同步功能分支与基础分支
sync_feature_with_base() {
    local feature_branch="$1"
    local base_branch
    base_branch=$(config_epic_get "base_branch")
    
    ui_subheader "基础分支同步"
    echo "  🔗 功能分支: $feature_branch"
    echo "  🔗 基础分支: $base_branch"
    echo
    
    # 检查基础分支是否有新的提交
    local behind_count
    behind_count=$(git rev-list --count "$feature_branch..$base_branch" 2>/dev/null || echo "0")
    
    if [[ "$behind_count" == "0" ]]; then
        ui_success "✅ 功能分支已是最新，无需同步"
        return 0
    fi
    
    ui_info "📊 基础分支领先 $behind_count 个提交"
    
    if ! ui_confirm "确认从基础分支同步变更？"; then
        ui_info "取消同步操作"
        return 1
    fi
    
    # 执行基础分支同步
    execute_base_sync "$feature_branch" "$base_branch"
}

# 执行基础分支同步
execute_base_sync() {
    local feature_branch="$1"
    local base_branch="$2"
    
    # 切换到功能分支的工作树
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$feature_branch")
    
    if [[ ! -d "$worktree_path" ]]; then
        ui_error "功能分支工作树不存在: $worktree_path"
        return 1
    fi
    
    local original_dir
    original_dir=$(pwd)
    
    cd "$worktree_path" || {
        ui_error "无法进入工作树: $worktree_path"
        return 1
    }
    
    # 检查工作目录状态
    if ! git_is_clean; then
        ui_warning "工作目录不干净，请先提交或暂存更改"
        ui_info "当前状态: $(git_status_summary)"
        cd "$original_dir" || true
        return 1
    fi
    
    ui_loading "🔄 同步基础分支 '$base_branch' 的变更"
    
    if git merge --no-ff "$base_branch" --message "feat: 同步基础分支 $base_branch 的变更" >/dev/null 2>&1; then
        ui_success "✅ 基础分支同步成功"
        show_sync_summary "$feature_branch" "$base_branch"
    else
        ui_error "❌ 基础分支同步失败，存在冲突"
        
        # 处理冲突
        handle_merge_conflict "$feature_branch" "$base_branch" "$conflict_action"
    fi
    
    cd "$original_dir" || true
}

# 同步所有分支
sync_all_branches() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "Epic全量同步"
    
    # 获取所有Epic分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_info "当前Epic没有功能分支需要同步"
        return 0
    fi
    
    local branches_array=()
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            branches_array+=("$branch")
        fi
    done <<< "$feature_branches"
    
    ui_subheader "将要同步的分支"
    for branch in "${branches_array[@]}"; do
        echo "  🌿 $branch"
    done
    echo
    
    if ! ui_confirm "确认同步所有 ${#branches_array[@]} 个分支？"; then
        ui_info "取消全量同步"
        return 1
    fi
    
    # 逐个同步分支
    local success_count=0
    local total_count=${#branches_array[@]}
    
    for branch in "${branches_array[@]}"; do
        ui_loading "同步分支: $branch"
        
        if sync_feature_with_base "$branch"; then
            ((success_count++))
            ui_success "✅ $branch 同步成功"
        else
            ui_error "❌ $branch 同步失败"
        fi
    done
    
    # 显示同步结果摘要
    ui_subheader "同步结果"
    echo "  📊 总计: $total_count 个分支"
    echo "  ✅ 成功: $success_count 个分支"
    echo "  ❌ 失败: $((total_count - success_count)) 个分支"
    
    if [[ "$success_count" == "$total_count" ]]; then
        ui_success "🎉 所有分支同步成功！"
    else
        ui_warning "⚠️ 部分分支同步失败，请检查失败的分支"
    fi
}

# 同步特定功能
sync_specific_feature() {
    local feature_name="$1"
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 验证功能名称格式
    if [[ ! "$feature_name" =~ ^$epic_name/ ]]; then
        feature_name="$epic_name/$feature_name"
    fi
    
    if ! git_branch_exists "$feature_name"; then
        ui_error "功能分支不存在: $feature_name"
        return 1
    fi
    
    ui_header "功能同步: $feature_name"
    
    # 提供同步选项
    local sync_options=(
        "同步依赖关系"
        "同步基础分支"
        "同步全部（依赖+基础）"
        "取消操作"
    )
    
    local choice
    choice=$(ui_select_menu "选择同步类型" "${sync_options[@]}")
    
    case $choice in
        0) # 同步依赖
            sync_dependencies "$feature_name"
            ;;
        1) # 同步基础分支
            sync_feature_with_base "$feature_name"
            ;;
        2) # 同步全部
            ui_info "执行完整同步: $feature_name"
            if sync_dependencies "$feature_name"; then
                sync_feature_with_base "$feature_name"
            fi
            ;;
        3) # 取消
            ui_info "取消同步操作"
            return 1
            ;;
    esac
}

# 选择要同步的功能
select_feature_for_sync() {
    local epic_name="$1"
    
    # 获取所有Epic功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_warning "当前Epic没有功能分支"
        return 1
    fi
    
    local branches_array=()
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            branches_array+=("$branch")
        fi
    done <<< "$feature_branches"
    
    # 添加取消选项
    branches_array+=("取消操作")
    
    local choice
    choice=$(ui_select_menu "选择要同步的功能" "${branches_array[@]}")
    
    if [[ $choice -eq $((${#branches_array[@]} - 1)) ]]; then
        # 用户选择取消
        ui_info "取消同步操作"
        return 1
    fi
    
    local selected_feature="${branches_array[$choice]}"
    sync_dependencies "$selected_feature"
}

# 显示同步摘要
show_sync_summary() {
    local feature_branch="$1"
    local source_branch="$2"
    
    ui_subheader "同步摘要"
    echo "  🔗 目标分支: $feature_branch"
    echo "  🔗 源分支: $source_branch"
    echo "  ⏰ 同步时间: $(current_iso_timestamp)"
    
    # 显示新增的提交
    local new_commits
    new_commits=$(git rev-list --count HEAD~1..HEAD 2>/dev/null || echo "1")
    echo "  📝 新增提交: $new_commits 个"
    
    # 显示影响的文件
    local changed_files
    changed_files=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | wc -l | tr -d ' ')
    echo "  📁 影响文件: $changed_files 个"
    echo
    
    ui_info "💡 建议: 运行测试确保同步后的代码正常工作"
    ui_info "💡 提示: 使用 'git-pr-flow status' 查看Epic整体状态"
}

# 处理合并冲突 - AI友好的冲突信息展示
handle_merge_conflict() {
    local feature_branch="$1"
    local source_branch="$2"
    local conflict_action="${3:-}"  # 可选的明确处理动作
    
    # 显示详细的冲突分析
    show_detailed_conflict_info "$feature_branch" "$source_branch"
    
    # 根据是否有明确的处理动作决定行为
    if [[ -n "$conflict_action" ]]; then
        # 有明确的处理动作，执行相应操作
        execute_conflict_resolution "$conflict_action"
    else
        # 没有明确动作，显示指导信息并中止合并
        show_conflict_resolution_guide "$feature_branch" "$source_branch"
        git merge --abort >/dev/null 2>&1 || true
        return 1
    fi
}

# 显示详细的冲突信息（AI友好）
show_detailed_conflict_info() {
    local feature_branch="$1"
    local source_branch="$2"
    
    ui_error "❌ 合并冲突检测"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # 基本信息
    echo "📋 冲突概况:"
    echo "  源分支: $source_branch"
    echo "  目标分支: $feature_branch"
    echo "  冲突原因: 两个分支修改了相同的文件区域"
    echo
    
    # 冲突文件列表
    local conflict_files
    conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    if [[ -n "$conflict_files" ]]; then
        echo "⚠️ 冲突文件列表:"
        local file_count=0
        while IFS= read -r file; do
            ((file_count++))
            echo "  $file_count. $file"
            
            # 显示每个文件的冲突统计
            local conflict_sections
            conflict_sections=$(grep -c "^<<<<<<< " "$file" 2>/dev/null || echo "0")
            echo "     └─ 冲突区域: $conflict_sections 处"
        done <<< "$conflict_files"
        echo
    fi
    
    # 冲突详细分析
    echo "🔍 冲突分析:"
    local total_conflicts=0
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            local file_conflicts
            file_conflicts=$(grep -c "^<<<<<<< " "$file" 2>/dev/null || echo "0")
            total_conflicts=$((total_conflicts + file_conflicts))
            
            echo "  📄 $file:"
            echo "     └─ 冲突标记: $file_conflicts 处"
            
            # 显示冲突预览（前3行）
            if [[ $file_conflicts -gt 0 ]]; then
                echo "     └─ 预览:"
                grep -A 2 -B 1 "^<<<<<<< " "$file" 2>/dev/null | head -6 | while IFS= read -r line; do
                    echo "        $line"
                done
                if [[ $file_conflicts -gt 1 ]]; then
                    echo "        ... (还有 $((file_conflicts - 1)) 处冲突)"
                fi
            fi
            echo
        fi
    done <<< "$conflict_files"
    
    echo "📊 冲突统计:"
    echo "  总冲突文件: $(echo "$conflict_files" | wc -l | tr -d ' ') 个"
    echo "  总冲突区域: $total_conflicts 处"
    echo
}

# 显示冲突解决指导（AI友好）
show_conflict_resolution_guide() {
    local feature_branch="$1" 
    local source_branch="$2"
    
    echo "🛠️ 冲突解决选项:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    echo "选项1: 手动解决冲突"
    echo "  📝 适用场景: 需要仔细合并代码逻辑"
    echo "  📝 操作步骤:"
    echo "     1. 编辑冲突文件，解决 <<<<<<< ======= >>>>>>> 标记"
    echo "     2. 运行: git add <已解决的文件>"
    echo "     3. 运行: git commit"
    echo "  📝 风险等级: 低（推荐）"
    echo
    
    echo "选项2: 放弃此次合并"
    echo "  📝 适用场景: 暂时无法处理冲突，需要稍后再试"
    echo "  📝 执行命令: gpf sync --abort"
    echo "  📝 风险等级: 无"
    echo
    
    echo "选项3: 跳过冲突分支"
    echo "  📝 适用场景: 确认当前分支可以暂时跳过"
    echo "  📝 执行命令: gpf sync --skip"
    echo "  📝 风险等级: 中等（可能导致功能不完整）"
    echo
    
    echo "选项4: 使用源分支内容"
    echo "  📝 适用场景: 确认源分支的更改更重要"
    echo "  📝 执行命令: gpf sync --accept-source"
    echo "  📝 风险等级: 高（会丢失当前分支的更改）"
    echo
    
    echo "选项5: 使用目标分支内容"
    echo "  📝 适用场景: 确认当前分支的内容应该保留"
    echo "  📝 执行命令: gpf sync --accept-target"
    echo "  📝 风险等级: 高（会忽略源分支的更改）"
    echo
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 AI助手建议:"
    echo "如果你是AI助手，请仔细阅读上述冲突信息和解决选项。"
    echo "基于冲突的性质和上下文，选择最合适的解决方案。"
    echo "然后使用相应的命令重新执行同步操作。"
    echo
    echo "⚠️ 重要提醒:"
    echo "同步操作已被中止以避免数据丢失。"
    echo "请明确选择处理方式后，使用带参数的命令重新执行。"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 执行冲突解决
execute_conflict_resolution() {
    local action="$1"
    
    case "$action" in
        "abort")
            ui_info "🔄 中止合并操作"
            git merge --abort >/dev/null 2>&1 || true
            return 1
            ;;
        "skip")
            ui_warning "⏭️ 跳过当前冲突分支"
            git merge --abort >/dev/null 2>&1 || true
            return 2  # 特殊返回码表示跳过
            ;;
        "accept-source")
            ui_warning "⚠️ 接受源分支内容（丢失当前分支更改）"
            git merge --abort >/dev/null 2>&1 || true
            git merge -X theirs HEAD >/dev/null 2>&1
            ;;
        "accept-target")
            ui_warning "⚠️ 接受目标分支内容（忽略源分支更改）"
            git merge --abort >/dev/null 2>&1 || true
            git merge -X ours HEAD >/dev/null 2>&1
            ;;
        *)
            ui_error "未知的冲突解决动作: $action"
            return 1
            ;;
    esac
}

# 显示sync命令帮助信息
show_sync_help() {
    cat << 'EOF'
Git PR Flow - sync 命令

用法:
  gpf sync [选项] [范围] [目标]

范围:
  deps        同步当前功能的依赖关系 (默认)
  base        同步基础分支变更
  all         同步整个Epic的所有分支
  feature     同步特定功能分支

基础选项:
  -y, --auto-confirm        自动确认安全操作
  --strategy <策略>         指定同步策略 (deps|base|all)
  -h, --help               显示此帮助信息

冲突解决选项 (用于明确处理冲突):
  --abort                  中止当前合并操作
  --skip                   跳过冲突分支，继续处理其他分支
  --accept-source          使用源分支内容 (丢失当前分支更改)
  --accept-target          使用目标分支内容 (忽略源分支更改)

基础示例:
  gpf sync                              # 同步当前功能依赖
  gpf sync base                         # 同步基础分支
  gpf sync all                          # 同步整个Epic
  gpf sync feature auth/login           # 同步特定功能分支

冲突处理工作流:
  1. 执行 gpf sync                      # 显示详细冲突信息
  2. 阅读冲突分析和解决选项
  3. 选择处理方式:
     - 手动解决: 编辑文件后 git add + git commit
     - 中止合并: gpf sync --abort
     - 跳过分支: gpf sync --skip
     - 接受源分支: gpf sync --accept-source
     - 接受目标分支: gpf sync --accept-target

AI助手友好设计:
  当遇到冲突时，sync命令会显示:
  ✅ 详细的冲突文件列表和统计
  ✅ 每个冲突的具体位置和预览
  ✅ 明确的解决选项和风险说明
  ✅ 具体的命令建议

  AI助手可以：
  1. 阅读详细的冲突信息
  2. 理解每种解决方案的适用场景和风险
  3. 基于上下文选择合适的处理方式
  4. 使用明确的参数重新执行命令

安全设计原则:
  - 默认展示信息，不做危险决策
  - 冲突处理需要明确的参数表达意图  
  - 高风险操作会显示警告信息
  - 操作可逆，支持中止和重试

高级示例:
  # 分析冲突后的明确处理
  gpf sync base                         # 1. 显示冲突信息
  gpf sync base --skip                  # 2. 决定跳过冲突分支
  
  # 自动确认安全操作
  gpf sync -y --strategy all            # 自动确认，但冲突仍需明确处理
EOF
}