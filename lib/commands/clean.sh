#!/usr/bin/env bash

# Git PR Flow - clean命令实现
# 智能环境清理，支持工作树、分支、Epic级清理

# clean命令主函数
cmd_clean() {
    local scope="${1:-interactive}"
    local target="${2:-}"
    
    case "$scope" in
        "interactive")
            handle_clean_interactive
            ;;
        "worktrees")
            clean_worktrees "$target"
            ;;
        "branches")
            clean_branches "$target"
            ;;
        "epic")
            clean_epic "$target"
            ;;
        "merged")
            clean_merged_branches
            ;;
        "all")
            clean_all_with_confirmation
            ;;
        "--release")
            clean_after_release
            ;;
        *)
            ui_error "无效的清理范围: $scope"
            ui_info "支持的范围: interactive, worktrees, branches, epic, merged, all"
            ui_info "用法示例:"
            ui_info "  git-pr-flow clean                    # 交互式清理"
            ui_info "  git-pr-flow clean worktrees          # 清理未使用的工作树"
            ui_info "  git-pr-flow clean branches           # 清理已合并分支"
            ui_info "  git-pr-flow clean epic <epic-name>   # 清理指定Epic"
            ui_info "  git-pr-flow clean merged             # 清理已合并分支"
            ui_info "  git-pr-flow clean all                # 全面清理"
            ui_info "  git-pr-flow clean --release          # 发布后清理"
            return 1
            ;;
    esac
}

# 交互式清理处理
handle_clean_interactive() {
    ui_header "智能环境清理"
    
    # 检查当前状态
    local cleanup_context
    cleanup_context=$(analyze_cleanup_context)
    
    # 显示当前状态摘要
    show_cleanup_context "$cleanup_context"
    
    # 提供清理选项
    local cleanup_options=(
        "清理未使用的工作树"
        "清理已合并的分支"
        "清理当前Epic环境"
        "全面环境清理"
        "查看详细状态"
        "取消操作"
    )
    
    local choice
    choice=$(ui_select_menu "选择清理操作" "${cleanup_options[@]}")
    
    case $choice in
        0) # 清理工作树
            clean_worktrees
            ;;
        1) # 清理已合并分支
            clean_merged_branches
            ;;
        2) # 清理当前Epic
            if config_epic_exists; then
                local epic_name
                epic_name=$(config_epic_get "epic_name")
                clean_epic "$epic_name"
            else
                ui_warning "未找到Epic配置"
            fi
            ;;
        3) # 全面清理
            clean_all_with_confirmation
            ;;
        4) # 查看详细状态
            show_detailed_cleanup_status
            ;;
        5) # 取消操作
            ui_info "取消清理操作"
            return 0
            ;;
    esac
}

# 分析清理上下文
analyze_cleanup_context() {
    local total_worktrees unused_worktrees merged_branches epic_branches
    
    # 统计工作树
    total_worktrees=$(git_list_worktrees | grep -c "^worktree" || echo "0")
    unused_worktrees=$(count_unused_worktrees)
    
    # 统计分支
    merged_branches=$(count_merged_branches)
    epic_branches=$(git_list_epic_branches | wc -l | tr -d ' ')
    
    cat << EOF
{
    "total_worktrees": $total_worktrees,
    "unused_worktrees": $unused_worktrees,
    "merged_branches": $merged_branches,
    "epic_branches": $epic_branches,
    "has_epic_config": $(if config_epic_exists; then echo "true"; else echo "false"; fi)
}
EOF
}

# 显示清理上下文
show_cleanup_context() {
    local context="$1"
    
    ui_subheader "当前环境状态"
    
    local total_worktrees unused_worktrees merged_branches epic_branches has_epic_config
    total_worktrees=$(echo "$context" | grep '"total_worktrees"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    unused_worktrees=$(echo "$context" | grep '"unused_worktrees"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    merged_branches=$(echo "$context" | grep '"merged_branches"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    epic_branches=$(echo "$context" | grep '"epic_branches"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    has_epic_config=$(echo "$context" | grep '"has_epic_config"' | cut -d':' -f2 | tr -d ' ,"')
    
    echo "  🏠 工作树总数: $total_worktrees"
    echo "  🧹 可清理工作树: $unused_worktrees"
    echo "  🌿 已合并分支: $merged_branches"
    echo "  🚀 Epic分支: $epic_branches"
    
    if [[ "$has_epic_config" == "true" ]]; then
        local epic_name
        epic_name=$(config_epic_get "epic_name")
        echo "  📋 当前Epic: $epic_name"
    else
        echo "  📋 当前Epic: 无"
    fi
    echo
}

# 统计未使用的工作树
count_unused_worktrees() {
    local count=0
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local worktree_path="${BASH_REMATCH[1]}"
            local branch_name
            branch_name=$(git_worktree_branch "$worktree_path")
            
            # 检查是否是主工作树
            if [[ "$worktree_path" == "$(git rev-parse --show-toplevel)" ]]; then
                continue
            fi
            
            # 检查工作树是否有未提交的更改
            if [[ -d "$worktree_path" ]]; then
                local original_dir
                original_dir=$(pwd)
                cd "$worktree_path" || continue
                
                if git_is_clean && ! git_has_untracked; then
                    ((count++))
                fi
                
                cd "$original_dir" || true
            fi
        fi
    done <<< "$worktree_info"
    
    echo "$count"
}

# 统计已合并分支
count_merged_branches() {
    local count=0
    local all_branches current_branch
    all_branches=$(git_list_branches)
    current_branch=$(git_current_branch)
    
    # 获取主要分支列表
    local main_branches=("main" "master" "develop" "staging")
    
    while IFS= read -r branch; do
        if [[ -n "$branch" && "$branch" != "$current_branch" ]]; then
            # 检查是否是主要分支
            local is_main_branch=false
            for main_branch in "${main_branches[@]}"; do
                if [[ "$branch" == "$main_branch" ]]; then
                    is_main_branch=true
                    break
                fi
            done
            
            if [[ "$is_main_branch" == "false" ]]; then
                # 检查是否已合并到主分支
                for main_branch in "${main_branches[@]}"; do
                    if git_branch_exists "$main_branch"; then
                        if git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
                            ((count++))
                            break
                        fi
                    fi
                done
            fi
        fi
    done <<< "$all_branches"
    
    echo "$count"
}

# 清理工作树
clean_worktrees() {
    local target_pattern="$1"
    
    ui_subheader "清理工作树"
    
    # 获取所有工作树
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    local worktrees_to_clean=()
    local main_worktree
    main_worktree=$(git rev-parse --show-toplevel)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local worktree_path="${BASH_REMATCH[1]}"
            
            # 跳过主工作树
            if [[ "$worktree_path" == "$main_worktree" ]]; then
                continue
            fi
            
            # 如果指定了模式，进行匹配
            if [[ -n "$target_pattern" && ! "$worktree_path" =~ $target_pattern ]]; then
                continue
            fi
            
            # 检查是否可以安全清理
            if can_clean_worktree "$worktree_path"; then
                worktrees_to_clean+=("$worktree_path")
            fi
        fi
    done <<< "$worktree_info"
    
    if [[ ${#worktrees_to_clean[@]} -eq 0 ]]; then
        ui_info "  📝 没有找到可清理的工作树"
        return 0
    fi
    
    # 显示要清理的工作树
    echo "  发现 ${#worktrees_to_clean[@]} 个可清理的工作树:"
    for worktree in "${worktrees_to_clean[@]}"; do
        local branch_name
        branch_name=$(git_worktree_branch "$worktree")
        echo "    🧹 $worktree (分支: $branch_name)"
    done
    echo
    
    if ! ui_confirm "确认清理这些工作树？"; then
        ui_info "取消工作树清理"
        return 0
    fi
    
    # 执行清理
    local cleaned_count=0
    for worktree in "${worktrees_to_clean[@]}"; do
        ui_loading "清理工作树: $worktree"
        
        if git_remove_worktree "$worktree" true; then
            ((cleaned_count++))
            echo "    ✅ $worktree 清理成功"
        else
            echo "    ❌ $worktree 清理失败"
        fi
    done
    
    echo
    ui_success "🎉 清理完成: $cleaned_count/${#worktrees_to_clean[@]} 个工作树"
}

# 检查工作树是否可以安全清理
can_clean_worktree() {
    local worktree_path="$1"
    
    if [[ ! -d "$worktree_path" ]]; then
        return 0  # 目录不存在，可以清理
    fi
    
    local original_dir
    original_dir=$(pwd)
    
    cd "$worktree_path" || return 1
    
    # 检查是否有未提交的更改
    local can_clean=true
    if ! git_is_clean || git_has_untracked; then
        can_clean=false
    fi
    
    cd "$original_dir" || true
    
    [[ "$can_clean" == "true" ]]
}

# 清理分支
clean_branches() {
    local target_pattern="$1"
    
    ui_subheader "清理分支"
    
    if [[ -n "$target_pattern" ]]; then
        clean_branches_by_pattern "$target_pattern"
    else
        clean_merged_branches
    fi
}

# 按模式清理分支
clean_branches_by_pattern() {
    local pattern="$1"
    
    ui_info "🔍 查找匹配模式的分支: $pattern"
    
    local matching_branches=()
    local all_branches
    all_branches=$(git_list_branches)
    
    while IFS= read -r branch; do
        if [[ -n "$branch" && "$branch" =~ $pattern ]]; then
            matching_branches+=("$branch")
        fi
    done <<< "$all_branches"
    
    if [[ ${#matching_branches[@]} -eq 0 ]]; then
        ui_info "  📝 没有找到匹配的分支"
        return 0
    fi
    
    echo "  发现 ${#matching_branches[@]} 个匹配的分支:"
    for branch in "${matching_branches[@]}"; do
        echo "    🌿 $branch"
    done
    echo
    
    if ! ui_confirm "确认删除这些分支？"; then
        ui_info "取消分支清理"
        return 0
    fi
    
    # 执行删除
    local deleted_count=0
    for branch in "${matching_branches[@]}"; do
        if delete_branch_safe "$branch"; then
            ((deleted_count++))
        fi
    done
    
    ui_success "🎉 清理完成: $deleted_count/${#matching_branches[@]} 个分支"
}

# 清理已合并分支
clean_merged_branches() {
    ui_info "🔍 查找已合并的分支..."
    
    local merged_branches=()
    local all_branches current_branch
    all_branches=$(git_list_branches)
    current_branch=$(git_current_branch)
    
    # 主要分支列表
    local main_branches=("main" "master" "develop" "staging")
    
    while IFS= read -r branch; do
        if [[ -n "$branch" && "$branch" != "$current_branch" ]]; then
            # 检查是否是主要分支
            local is_main_branch=false
            for main_branch in "${main_branches[@]}"; do
                if [[ "$branch" == "$main_branch" ]]; then
                    is_main_branch=true
                    break
                fi
            done
            
            if [[ "$is_main_branch" == "false" ]]; then
                # 检查是否已合并
                if is_branch_merged "$branch"; then
                    merged_branches+=("$branch")
                fi
            fi
        fi
    done <<< "$all_branches"
    
    if [[ ${#merged_branches[@]} -eq 0 ]]; then
        ui_info "  📝 没有找到已合并的分支"
        return 0
    fi
    
    echo "  发现 ${#merged_branches[@]} 个已合并的分支:"
    for branch in "${merged_branches[@]}"; do
        echo "    🌿 $branch"
    done
    echo
    
    if ! ui_confirm "确认删除这些已合并的分支？"; then
        ui_info "取消已合并分支清理"
        return 0
    fi
    
    # 执行删除
    local deleted_count=0
    for branch in "${merged_branches[@]}"; do
        if delete_branch_safe "$branch"; then
            ((deleted_count++))
        fi
    done
    
    ui_success "🎉 清理完成: $deleted_count/${#merged_branches[@]} 个分支"
}

# 检查分支是否已合并
is_branch_merged() {
    local branch="$1"
    
    # 检查是否合并到主要分支
    local main_branches=("main" "master" "develop")
    
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            if git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
                return 0
            fi
        fi
    done
    
    return 1
}

# 安全删除分支
delete_branch_safe() {
    local branch="$1"
    
    ui_loading "删除分支: $branch"
    
    # 检查分支是否被工作树使用
    if git_branch_in_worktree "$branch"; then
        echo "    ⚠️ $branch 正被工作树使用，跳过删除"
        return 1
    fi
    
    # 删除分支
    if git branch -d "$branch" >/dev/null 2>&1; then
        echo "    ✅ $branch 删除成功"
        return 0
    elif git branch -D "$branch" >/dev/null 2>&1; then
        echo "    ✅ $branch 强制删除成功"
        return 0
    else
        echo "    ❌ $branch 删除失败"
        return 1
    fi
}

# 清理Epic
clean_epic() {
    local epic_name="$1"
    
    if [[ -z "$epic_name" ]]; then
        if config_epic_exists; then
            epic_name=$(config_epic_get "epic_name")
        else
            ui_error "未指定Epic名称且未找到Epic配置"
            return 1
        fi
    fi
    
    ui_subheader "清理Epic: $epic_name"
    
    # 获取Epic相关资源
    local epic_branches epic_worktrees
    epic_branches=$(git_list_branches | grep "^$epic_name/" || true)
    epic_worktrees=$(get_epic_worktrees "$epic_name")
    
    # 显示将要清理的资源
    show_epic_cleanup_preview "$epic_name" "$epic_branches" "$epic_worktrees"
    
    if ! ui_confirm "确认清理整个Epic '$epic_name'？"; then
        ui_info "取消Epic清理"
        return 0
    fi
    
    # 执行Epic清理
    execute_epic_cleanup "$epic_name" "$epic_branches" "$epic_worktrees"
}

# 获取Epic工作树
get_epic_worktrees() {
    local epic_name="$1"
    local epic_worktrees=""
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local worktree_path="${BASH_REMATCH[1]}"
            local branch_name
            branch_name=$(git_worktree_branch "$worktree_path")
            
            if [[ "$branch_name" =~ ^$epic_name/ ]]; then
                epic_worktrees+="$worktree_path"$'\n'
            fi
        fi
    done <<< "$worktree_info"
    
    echo -n "$epic_worktrees"
}

# 显示Epic清理预览
show_epic_cleanup_preview() {
    local epic_name="$1"
    local epic_branches="$2"
    local epic_worktrees="$3"
    
    echo "  📋 Epic: $epic_name"
    echo
    
    echo "  🌿 将删除的分支:"
    if [[ -n "$epic_branches" ]]; then
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                echo "    - $branch"
            fi
        done <<< "$epic_branches"
    else
        echo "    (无)"
    fi
    echo
    
    echo "  🏠 将删除的工作树:"
    if [[ -n "$epic_worktrees" ]]; then
        while IFS= read -r worktree; do
            if [[ -n "$worktree" ]]; then
                echo "    - $worktree"
            fi
        done <<< "$epic_worktrees"
    else
        echo "    (无)"
    fi
    echo
    
    # 检查Epic配置
    if config_epic_exists; then
        local current_epic
        current_epic=$(config_epic_get "epic_name")
        if [[ "$current_epic" == "$epic_name" ]]; then
            echo "  📝 将删除Epic配置文件"
            echo
        fi
    fi
}

# 执行Epic清理
execute_epic_cleanup() {
    local epic_name="$1"
    local epic_branches="$2"
    local epic_worktrees="$3"
    
    local cleanup_summary=""
    
    # 清理工作树
    if [[ -n "$epic_worktrees" ]]; then
        ui_loading "清理Epic工作树..."
        local worktree_count=0
        
        while IFS= read -r worktree; do
            if [[ -n "$worktree" ]]; then
                if git_remove_worktree "$worktree" true; then
                    ((worktree_count++))
                fi
            fi
        done <<< "$epic_worktrees"
        
        cleanup_summary+="工作树: $worktree_count 个; "
    fi
    
    # 清理分支
    if [[ -n "$epic_branches" ]]; then
        ui_loading "清理Epic分支..."
        local branch_count=0
        
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                if delete_branch_safe "$branch"; then
                    ((branch_count++))
                fi
            fi
        done <<< "$epic_branches"
        
        cleanup_summary+="分支: $branch_count 个; "
    fi
    
    # 清理Epic配置
    if config_epic_exists; then
        local current_epic
        current_epic=$(config_epic_get "epic_name")
        if [[ "$current_epic" == "$epic_name" ]]; then
            ui_loading "清理Epic配置..."
            if rm -f "$EPIC_CONFIG_FILE" 2>/dev/null; then
                cleanup_summary+="配置文件: 1 个; "
            fi
        fi
    fi
    
    ui_success "🎉 Epic '$epic_name' 清理完成"
    echo "  📊 清理摘要: $cleanup_summary"
}

# 全面清理（需要确认）
clean_all_with_confirmation() {
    ui_warning_box "⚠️ 全面环境清理" \
        "此操作将清理所有:" \
        "- 未使用的工作树" \
        "- 已合并的分支" \
        "- Epic配置文件" \
        "" \
        "此操作不可撤销！"
    
    if ! ui_confirm "确认执行全面清理？"; then
        ui_info "取消全面清理"
        return 0
    fi
    
    # 再次确认
    if ! ui_confirm "最后确认：真的要清理所有环境？"; then
        ui_info "取消全面清理"
        return 0
    fi
    
    ui_loading "执行全面环境清理..."
    
    # 1. 清理工作树
    echo "  🧹 清理工作树..."
    clean_worktrees >/dev/null 2>&1
    
    # 2. 清理已合并分支
    echo "  🌿 清理已合并分支..."
    clean_merged_branches >/dev/null 2>&1
    
    # 3. 清理Epic配置
    if config_epic_exists; then
        echo "  📝 清理Epic配置..."
        rm -f "$EPIC_CONFIG_FILE" 2>/dev/null
    fi
    
    # 4. 清理临时文件
    echo "  🗑️ 清理临时文件..."
    find . -name "epic-*-readiness-report.md" -type f -delete 2>/dev/null || true
    find . -name "CHANGELOG-*.md" -type f -delete 2>/dev/null || true
    
    ui_success "🎉 全面清理完成！环境已重置"
}

# 发布后清理
clean_after_release() {
    ui_header "发布后环境清理"
    
    if ! config_epic_exists; then
        ui_error "未找到Epic配置，无法执行发布后清理"
        return 1
    fi
    
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_info "🎉 恭喜！Epic '$epic_name' 发布成功"
    ui_info "开始发布后清理流程..."
    echo
    
    # 显示发布后清理选项
    local cleanup_options=(
        "保留所有分支和工作树（推荐）"
        "清理已合并的功能分支"
        "清理所有Epic相关资源"
        "仅清理工作树，保留分支"
        "取消清理"
    )
    
    local choice
    choice=$(ui_select_menu "选择发布后清理策略" "${cleanup_options[@]}")
    
    case $choice in
        0) # 保留所有
            ui_success "✅ 保留所有资源，便于后续维护"
            ;;
        1) # 清理已合并分支
            clean_merged_epic_branches "$epic_name"
            ;;
        2) # 清理所有Epic资源
            clean_epic "$epic_name"
            ;;
        3) # 仅清理工作树
            clean_epic_worktrees "$epic_name"
            ;;
        4) # 取消
            ui_info "取消发布后清理"
            ;;
    esac
    
    # 生成发布摘要
    generate_release_summary "$epic_name"
}

# 清理已合并的Epic分支
clean_merged_epic_branches() {
    local epic_name="$1"
    
    ui_info "🔍 查找已合并的Epic分支..."
    
    local epic_branches merged_branches=()
    epic_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    while IFS= read -r branch; do
        if [[ -n "$branch" && "$(is_branch_merged "$branch")" ]]; then
            merged_branches+=("$branch")
        fi
    done <<< "$epic_branches"
    
    if [[ ${#merged_branches[@]} -eq 0 ]]; then
        ui_info "  📝 没有找到已合并的Epic分支"
        return 0
    fi
    
    echo "  发现 ${#merged_branches[@]} 个已合并的分支:"
    for branch in "${merged_branches[@]}"; do
        echo "    🌿 $branch"
    done
    echo
    
    if ui_confirm "清理这些已合并的分支？"; then
        for branch in "${merged_branches[@]}"; do
            delete_branch_safe "$branch"
        done
        ui_success "✅ 已合并分支清理完成"
    fi
}

# 清理Epic工作树
clean_epic_worktrees() {
    local epic_name="$1"
    
    ui_info "🧹 清理Epic工作树..."
    
    local epic_worktrees
    epic_worktrees=$(get_epic_worktrees "$epic_name")
    
    if [[ -z "$epic_worktrees" ]]; then
        ui_info "  📝 没有找到Epic工作树"
        return 0
    fi
    
    while IFS= read -r worktree; do
        if [[ -n "$worktree" ]]; then
            git_remove_worktree "$worktree" true
        fi
    done <<< "$epic_worktrees"
    
    ui_success "✅ Epic工作树清理完成"
}

# 生成发布摘要
generate_release_summary() {
    local epic_name="$1"
    local summary_file="release-summary-$epic_name.md"
    
    cat > "$summary_file" << EOF
# $epic_name Epic 发布摘要

## 发布信息
- **Epic名称**: $epic_name
- **发布时间**: $(current_local_timestamp)
- **发布分支**: release/$epic_name

## 发布统计
- **功能分支数**: $(git_list_branches | grep -c "^$epic_name/" || echo "0")
- **总提交数**: $(git_list_branches | grep "^$epic_name/" | xargs -I {} git rev-list --count {} 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
- **变更文件**: 统计信息

## 后续维护
- 分支保留策略: 根据团队需求
- 监控和反馈: 收集用户反馈
- 问题修复: 准备hotfix流程

## 团队致谢
感谢所有参与此Epic开发的团队成员！

---
*发布摘要由 git-pr-flow 自动生成*
EOF
    
    ui_info "📄 发布摘要已生成: $summary_file"
}

# 显示详细清理状态
show_detailed_cleanup_status() {
    ui_header "详细清理状态分析"
    
    # 显示工作树详情
    ui_subheader "工作树分析"
    show_worktrees_analysis
    
    # 显示分支详情
    ui_subheader "分支分析"
    show_branches_analysis
    
    # 显示磁盘使用情况
    ui_subheader "磁盘使用分析"
    show_disk_usage_analysis
}

# 显示工作树分析
show_worktrees_analysis() {
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local worktree_path="${BASH_REMATCH[1]}"
            local branch_name
            branch_name=$(git_worktree_branch "$worktree_path")
            
            local size_info="未知"
            if [[ -d "$worktree_path" ]]; then
                size_info=$(du -sh "$worktree_path" 2>/dev/null | cut -f1 || echo "未知")
            fi
            
            local status_text
            if can_clean_worktree "$worktree_path"; then
                status_text="✅ 可清理"
            else
                status_text="⚠️ 有未提交更改"
            fi
            
            echo "  🏠 $worktree_path"
            echo "    ├─ 分支: $branch_name"
            echo "    ├─ 大小: $size_info"
            echo "    └─ 状态: $status_text"
        fi
    done <<< "$worktree_info"
}

# 显示分支分析
show_branches_analysis() {
    local all_branches
    all_branches=$(git_list_branches)
    
    local epic_count=0
    local merged_count=0
    local active_count=0
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            if [[ "$branch" =~ / ]]; then
                ((epic_count++))
            fi
            
            if is_branch_merged "$branch"; then
                ((merged_count++))
            else
                ((active_count++))
            fi
        fi
    done <<< "$all_branches"
    
    echo "  📊 分支统计:"
    echo "    ├─ Epic分支: $epic_count"
    echo "    ├─ 已合并: $merged_count"
    echo "    └─ 活跃分支: $active_count"
}

# 显示磁盘使用分析
show_disk_usage_analysis() {
    local git_dir_size worktrees_size
    git_dir_size=$(du -sh .git 2>/dev/null | cut -f1 || echo "未知")
    
    if [[ -d ".worktrees" ]]; then
        worktrees_size=$(du -sh .worktrees 2>/dev/null | cut -f1 || echo "未知")
    else
        worktrees_size="0B"
    fi
    
    echo "  💾 磁盘使用情况:"
    echo "    ├─ Git目录: $git_dir_size"
    echo "    └─ 工作树: $worktrees_size"
}