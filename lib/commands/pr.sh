#!/usr/bin/env bash

# Git PR Flow - pr命令实现
# 智能PR创建，支持Epic上下文、依赖关系和策略性发布

# pr命令主函数
cmd_pr() {
    local feature_name="${1:-}"
    local target_branch="${2:-}"
    
    # 检查Epic配置
    if ! config_epic_exists; then
        ui_error "未找到Epic配置文件"
        ui_info "请先运行: git-pr-flow init <epic-name>"
        return 1
    fi
    
    if ! config_epic_validate; then
        ui_error "Epic配置文件无效"
        return 1
    fi
    
    # 如果没有提供功能名称，显示交互式选择
    if [[ -z "$feature_name" ]]; then
        if ! handle_pr_interactive; then
            return 1
        fi
        return 0
    fi
    
    # 验证并处理功能名称
    local full_feature_name
    full_feature_name=$(normalize_feature_name "$feature_name")
    
    if [[ -z "$full_feature_name" ]]; then
        ui_error "无效的功能名称: $feature_name"
        return 1
    fi
    
    # 执行PR创建
    create_feature_pr "$full_feature_name" "$target_branch"
}

# 交互式PR创建处理
handle_pr_interactive() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "创建智能PR"
    ui_info "当前Epic: $epic_name ($(config_epic_get "description"))"
    
    # 获取可创建PR的功能分支
    local available_features
    available_features=$(get_pr_ready_features "$epic_name")
    
    if [[ -z "$available_features" ]]; then
        ui_warning "没有可以创建PR的功能分支"
        ui_info "请确保功能分支有未推送的提交"
        return 1
    fi
    
    ui_subheader "可创建PR的功能"
    
    local features_array=()
    while IFS= read -r feature; do
        if [[ -n "$feature" ]]; then
            features_array+=("$feature")
            local commit_count ahead_count
            commit_count=$(git rev-list --count "$feature" 2>/dev/null || echo "0")
            ahead_count=$(get_feature_ahead_count "$feature")
            echo "  📋 $feature ($commit_count 提交, $ahead_count 未推送)"
        fi
    done <<< "$available_features"
    echo
    
    # 添加操作选项
    local options=("${features_array[@]}")
    options+=("查看Epic整体状态")
    options+=("取消操作")
    
    local choice
    choice=$(ui_select_menu "选择要创建PR的功能" "${options[@]}")
    
    if [[ $choice -eq $((${#options[@]} - 1)) ]]; then
        # 取消操作
        ui_info "取消PR创建"
        return 1
    elif [[ $choice -eq $((${#options[@]} - 2)) ]]; then
        # 查看Epic状态
        source "$PROJECT_ROOT/lib/commands/status.sh"
        cmd_status
        return 0
    else
        # 选择了具体功能
        local selected_feature="${features_array[$choice]}"
        create_feature_pr "$selected_feature"
    fi
}

# 获取可以创建PR的功能分支
get_pr_ready_features() {
    local epic_name="$1"
    
    # 获取所有Epic功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        return 0
    fi
    
    # 筛选有提交且有工作树的分支
    local ready_features=""
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local worktree_path commit_count
            worktree_path=$(branch_to_worktree_path "$branch")
            commit_count=$(git rev-list --count "$branch" 2>/dev/null || echo "0")
            
            # 检查是否有工作树且有提交
            if [[ -d "$worktree_path" && "$commit_count" -gt 0 ]]; then
                ready_features+="$branch"$'\n'
            fi
        fi
    done <<< "$feature_branches"
    
    echo -n "$ready_features"
}

# 获取功能分支领先提交数
get_feature_ahead_count() {
    local feature_branch="$1"
    local base_branch
    base_branch=$(config_epic_get "base_branch")
    
    # 计算相对于基础分支的领先提交数
    git rev-list --count "$base_branch..$feature_branch" 2>/dev/null || echo "0"
}

# 标准化功能名称
normalize_feature_name() {
    local feature_name="$1"
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 如果已经包含Epic前缀，直接返回
    if [[ "$feature_name" =~ ^$epic_name/ ]]; then
        if git_branch_exists "$feature_name"; then
            echo "$feature_name"
        fi
        return 0
    fi
    
    # 添加Epic前缀
    local full_name="$epic_name/$feature_name"
    if git_branch_exists "$full_name"; then
        echo "$full_name"
        return 0
    fi
    
    # 如果都不存在，返回空
    return 1
}

# 创建功能PR
create_feature_pr() {
    local feature_name="$1"
    local target_branch="${2:-}"
    
    ui_loading "准备创建PR: $feature_name"
    
    # 验证功能分支存在
    if ! git_branch_exists "$feature_name"; then
        ui_error "功能分支不存在: $feature_name"
        return 1
    fi
    
    # 获取工作树路径
    local worktree_path
    worktree_path=$(branch_to_worktree_path "$feature_name")
    
    if [[ ! -d "$worktree_path" ]]; then
        ui_error "功能分支工作树不存在: $worktree_path"
        ui_info "请先运行: git-pr-flow start $feature_name"
        return 1
    fi
    
    # 分析PR上下文
    local pr_context
    pr_context=$(analyze_pr_context "$feature_name")
    
    # 显示PR预览
    show_pr_preview "$feature_name" "$pr_context"
    
    # 确认创建
    if ! ui_confirm "确认创建PR？"; then
        ui_info "取消PR创建"
        return 1
    fi
    
    # 执行PR创建流程
    execute_pr_creation "$feature_name" "$target_branch" "$pr_context"
}

# 分析PR上下文
analyze_pr_context() {
    local feature_name="$1"
    local epic_name base_branch
    epic_name=$(config_epic_get "epic_name")
    base_branch=$(config_epic_get "base_branch")
    
    # 创建上下文对象
    cat << EOF
{
    "feature_name": "$feature_name",
    "epic_name": "$epic_name", 
    "base_branch": "$base_branch",
    "commit_count": $(git rev-list --count "$feature_name" 2>/dev/null || echo "0"),
    "ahead_count": $(get_feature_ahead_count "$feature_name"),
    "dependencies": $(detect_pr_dependencies "$feature_name"),
    "changed_files": $(get_changed_files_count "$feature_name"),
    "worktree_path": "$(branch_to_worktree_path "$feature_name")"
}
EOF
}

# 检测PR依赖关系
detect_pr_dependencies() {
    local feature_name="$1"
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 获取同Epic下的其他分支
    local other_branches
    other_branches=$(git_list_branches | grep "^$epic_name/" | grep -v "^$feature_name$" || true)
    
    if [[ -z "$other_branches" ]]; then
        echo '[]'
        return 0
    fi
    
    # 检查是否基于其他分支创建
    local dependencies=()
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            # 检查是否包含该分支的提交
            local merge_base
            merge_base=$(git merge-base "$feature_name" "$branch" 2>/dev/null || echo "")
            local branch_head
            branch_head=$(git rev-parse "$branch" 2>/dev/null || echo "")
            
            if [[ -n "$merge_base" && "$merge_base" == "$branch_head" ]]; then
                dependencies+=("\"$branch\"")
            fi
        fi
    done <<< "$other_branches"
    
    if [[ ${#dependencies[@]} -gt 0 ]]; then
        echo "[$(IFS=,; echo "${dependencies[*]}")]"
    else
        echo '[]'
    fi
}

# 获取变更文件数量
get_changed_files_count() {
    local feature_name="$1"
    local base_branch
    base_branch=$(config_epic_get "base_branch")
    
    git diff --name-only "$base_branch..$feature_name" 2>/dev/null | wc -l | tr -d ' '
}

# 显示PR预览
show_pr_preview() {
    local feature_name="$1"
    local pr_context="$2"
    
    ui_subheader "PR预览"
    
    # 解析上下文信息
    local epic_name base_branch commit_count ahead_count changed_files
    epic_name=$(echo "$pr_context" | grep '"epic_name"' | cut -d'"' -f4)
    base_branch=$(echo "$pr_context" | grep '"base_branch"' | cut -d'"' -f4)
    commit_count=$(echo "$pr_context" | grep '"commit_count"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    ahead_count=$(echo "$pr_context" | grep '"ahead_count"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    changed_files=$(echo "$pr_context" | grep '"changed_files"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    
    echo "  📋 功能名称: $feature_name"
    echo "  🚀 所属Epic: $epic_name"
    echo "  🎯 目标分支: $base_branch"
    echo "  📝 总提交数: $commit_count"
    echo "  📈 新增提交: $ahead_count"
    echo "  📁 变更文件: $changed_files"
    
    # 显示依赖关系
    local dependencies
    dependencies=$(echo "$pr_context" | grep '"dependencies"' | cut -d':' -f2- | sed 's/[^[]*\[/[/' | sed 's/\].*/]/')
    if [[ "$dependencies" != "[]" ]]; then
        echo "  🔗 依赖分支: $dependencies"
    else
        echo "  🔗 依赖分支: 无"
    fi
    
    echo
    
    # 显示最近提交
    show_recent_commits "$feature_name" 5
}

# 显示最近提交
show_recent_commits() {
    local feature_name="$1"
    local limit="${2:-5}"
    
    ui_subheader "最近提交 (前$limit个)"
    
    # 切换到功能分支工作树
    local worktree_path original_dir
    worktree_path=$(branch_to_worktree_path "$feature_name")
    original_dir=$(pwd)
    
    if [[ -d "$worktree_path" ]]; then
        cd "$worktree_path" || return 1
        
        local commits
        commits=$(git log --oneline -n "$limit" 2>/dev/null || echo "")
        
        if [[ -n "$commits" ]]; then
            while IFS= read -r commit; do
                echo "    📝 $commit"
            done <<< "$commits"
        else
            echo "    (无提交记录)"
        fi
        
        cd "$original_dir" || true
    else
        echo "    (工作树不存在)"
    fi
    echo
}

# 执行PR创建
execute_pr_creation() {
    local feature_name="$1"
    local target_branch="$2"
    local pr_context="$3"
    
    ui_loading "🚀 创建PR: $feature_name"
    
    # 确定目标分支
    local final_target_branch
    if [[ -n "$target_branch" ]]; then
        final_target_branch="$target_branch"
    else
        final_target_branch=$(config_epic_get "base_branch")
    fi
    
    # 切换到功能分支工作树
    local worktree_path original_dir
    worktree_path=$(branch_to_worktree_path "$feature_name")
    original_dir=$(pwd)
    
    cd "$worktree_path" || {
        ui_error "无法进入工作树: $worktree_path"
        return 1
    }
    
    # 检查工作目录状态
    if ! git_is_clean; then
        ui_warning "工作目录不干净，请先提交更改"
        ui_info "当前状态: $(git_status_summary)"
        cd "$original_dir" || true
        return 1
    fi
    
    # 推送分支到远程
    ui_info "📤 推送分支到远程仓库"
    if ! git push origin "$feature_name" 2>/dev/null; then
        ui_warning "推送失败，尝试强制推送"
        if ! git push -f origin "$feature_name" 2>/dev/null; then
            ui_error "无法推送分支到远程"
            cd "$original_dir" || true
            return 1
        fi
    fi
    
    # 生成PR标题和描述
    local pr_title pr_body
    pr_title=$(generate_pr_title "$feature_name")
    pr_body=$(generate_pr_body "$feature_name" "$pr_context")
    
    # 创建PR（使用GitHub CLI或其他方法）
    if command_exists gh; then
        create_pr_with_gh "$feature_name" "$final_target_branch" "$pr_title" "$pr_body"
    else
        create_pr_manual "$feature_name" "$final_target_branch" "$pr_title" "$pr_body"
    fi
    
    cd "$original_dir" || true
}

# 生成PR标题
generate_pr_title() {
    local feature_name="$1"
    local feature_part="${feature_name#*/}"
    
    # 简单的标题生成逻辑
    echo "feat: 实现${feature_part}功能"
}

# 生成PR描述
generate_pr_body() {
    local feature_name="$1"
    local pr_context="$2"
    
    local epic_name base_branch commit_count changed_files
    epic_name=$(echo "$pr_context" | grep '"epic_name"' | cut -d'"' -f4)
    base_branch=$(echo "$pr_context" | grep '"base_branch"' | cut -d'"' -f4)
    commit_count=$(echo "$pr_context" | grep '"commit_count"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    changed_files=$(echo "$pr_context" | grep '"changed_files"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    
    cat << EOF
## 功能描述

此PR实现了 ${feature_name#*/} 功能，属于 **$epic_name** Epic的一部分。

## 变更概要

- 📝 提交数量: $commit_count
- 📁 变更文件: $changed_files
- 🎯 目标分支: $base_branch
- 🚀 Epic: $epic_name

## 测试计划

- [ ] 单元测试通过
- [ ] 集成测试通过  
- [ ] 手动测试验证
- [ ] 代码审查完成

## 相关链接

- Epic跟踪: 相关Epic开发进度
- 设计文档: 相关设计文档链接
- 需求文档: 相关需求文档链接

---
*此PR由 git-pr-flow 自动生成*
EOF
}

# 使用GitHub CLI创建PR
create_pr_with_gh() {
    local feature_name="$1"
    local target_branch="$2"
    local pr_title="$3"
    local pr_body="$4"
    
    ui_info "🔗 使用GitHub CLI创建PR"
    
    # 创建PR
    if gh pr create \
        --title "$pr_title" \
        --body "$pr_body" \
        --base "$target_branch" \
        --head "$feature_name" 2>/dev/null; then
        
        ui_success "✅ PR创建成功"
        
        # 获取PR URL
        local pr_url
        pr_url=$(gh pr view --json url --jq .url 2>/dev/null || echo "")
        if [[ -n "$pr_url" ]]; then
            echo "  🔗 PR链接: $pr_url"
        fi
        
        # 显示后续步骤
        show_pr_next_steps "$feature_name" "$pr_url"
    else
        ui_error "❌ GitHub CLI PR创建失败"
        ui_info "请手动创建PR或检查GitHub CLI配置"
        create_pr_manual "$feature_name" "$target_branch" "$pr_title" "$pr_body"
    fi
}

# 手动创建PR指引
create_pr_manual() {
    local feature_name="$1"
    local target_branch="$2"
    local pr_title="$3"
    local pr_body="$4"
    
    ui_warning "⚠️ 自动PR创建不可用，请手动创建"
    
    ui_info_box "手动创建PR指引" \
        "1. 访问GitHub仓库页面" \
        "2. 点击 'Compare & pull request'" \
        "3. 选择分支: $feature_name -> $target_branch" \
        "4. 使用以下信息:"
    
    echo "📋 PR标题:"
    echo "    $pr_title"
    echo
    echo "📝 PR描述:"
    echo "$pr_body" | sed 's/^/    /'
    echo
    
    ui_info "💡 提示: 安装GitHub CLI (gh) 可以自动创建PR"
    ui_info "💡 安装: brew install gh 或 https://cli.github.com/"
}

# 显示PR后续步骤
show_pr_next_steps() {
    local feature_name="$1"
    local pr_url="$2"
    
    ui_success_box "PR创建完成！" \
        "功能: $feature_name" \
        "状态: 等待审查" \
        "" \
        "后续步骤:" \
        "1. 等待代码审查" \
        "2. 根据反馈修改代码" \
        "3. 审查通过后合并" \
        "4. 使用 git-pr-flow clean 清理环境"
    
    if [[ -n "$pr_url" ]]; then
        echo "🔗 PR链接: $pr_url"
    fi
    echo
    
    echo "💻 快速操作:"
    echo "  git-pr-flow status           # 查看Epic进度"
    echo "  git-pr-flow sync             # 同步其他分支变更"
    echo "  git-pr-flow ready            # 检查Epic发布就绪状态"
    echo
}