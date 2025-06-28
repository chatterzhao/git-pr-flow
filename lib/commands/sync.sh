#!/usr/bin/env bash

# Git PR Flow - sync命令实现
# 智能同步依赖关系，处理Epic内分支间的同步和合并

# sync命令主函数
cmd_sync() {
    local scope="${1:-deps}"
    local target="${2:-}"
    
    # 检查Epic配置
    if ! config_epic_exists; then
        ui_error "未找到Epic配置文件"
        ui_info "请先运行: gpf init <epic-name>"
        return 1
    fi
    
    if ! config_epic_validate; then
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
    worktree_path=$(branch_to_worktree_path "$feature_branch")
    
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
        ui_info "请手动解决冲突后提交，或运行 git merge --abort 取消合并"
        
        # 显示冲突文件
        local conflict_files
        conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
        if [[ -n "$conflict_files" ]]; then
            ui_warning "冲突文件:"
            while IFS= read -r file; do
                echo "    ⚠️ $file"
            done <<< "$conflict_files"
        fi
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
    worktree_path=$(branch_to_worktree_path "$feature_branch")
    
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
        ui_info "请手动解决冲突后提交，或运行 git merge --abort 取消合并"
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