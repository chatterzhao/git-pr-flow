#!/usr/bin/env bash

# Git PR Flow - pr命令实现
# 智能PR创建，支持Epic上下文、依赖关系和策略性发布

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# 引入配置重构后的系统
[[ -f "$(dirname "${BASH_SOURCE[0]}")/../utils/config-context-bridge.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/../utils/config-context-bridge.sh"

# pr命令主函数
cmd_pr() {
    local feature_name=""
    local target_branch=""
    local push_remote=""
    local force_mode=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --push-remote)
                if [[ -n "$2" && "$2" != -* ]]; then
                    push_remote="$2"
                    shift 2
                else
                    ui_error "--push-remote 选项需要指定远程仓库名称"
                    return 1
                fi
                ;;
            --multi-platform)
                push_remote="multi-platform"
                shift
                ;;
            --target)
                if [[ -n "$2" && "$2" != -* ]]; then
                    target_branch="$2"
                    shift 2
                else
                    ui_error "--target 选项需要指定目标分支名称"
                    return 1
                fi
                ;;
            --force)
                force_mode=true
                shift
                ;;
            --help|-h)
                show_pr_help
                return 0
                ;;
            -*)
                ui_error "未知选项: $1"
                show_pr_help
                return 1
                ;;
            *)
                if [[ -z "$feature_name" ]]; then
                    feature_name="$1"
                elif [[ -z "$target_branch" ]]; then
                    target_branch="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 获取当前epic名称用于验证
    local epic_name
    epic_name=$(detect_current_epic)
    if [[ -z "$epic_name" ]]; then
        ui_error "无法检测当前Epic名称"
        ui_info "请确保在Epic工作环境中运行此命令"
        return 1
    fi
    
    # 检查Epic配置
    if ! config_epic_exists "$epic_name"; then
        ui_error "未找到Epic配置: $epic_name"
        ui_info "请先运行: gpf init <epic-name>"
        return 1
    fi

    if ! config_epic_validate "$epic_name"; then
        ui_error "Epic配置文件无效"
        return 1
    fi
    
    # 如果没有提供功能名称，根据当前上下文智能判断
    if [[ -z "$feature_name" ]]; then
        local context_result
        context_result=$(detect_pr_context)
        
        if [[ -n "$context_result" ]]; then
            # 自动检测到上下文，直接处理
            handle_context_pr "$context_result" "$target_branch" "$push_remote" "$force_mode"
        else
            # 无法自动检测，显示交互式选择
            if ! handle_pr_interactive "$force_mode"; then
                return 1
            fi
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
    create_feature_pr "$full_feature_name" "$target_branch" "$push_remote" "$force_mode"
}

# 检测当前PR上下文
detect_pr_context() {
    local current_dir=$(pwd)
    local current_branch=$(git branch --show-current 2>/dev/null || echo "")
    
    if [[ -z "$current_branch" ]]; then
        return 1
    fi
    
    # 检测当前位置类型
    if [[ "$current_dir" == *"/.worktrees/epic--"*"--"* ]]; then
        # 在功能分支工作树中：xx/yy -> epic/xx
        echo "feature:$current_branch"
        return 0
    elif [[ "$current_dir" == *"/.worktrees/epic--"* ]]; then
        # 在Epic分支工作树中：epic/xx -> develop
        echo "epic:$current_branch"
        return 0
    fi
    
    # 如果在项目根目录，根据分支名判断
    if [[ "$current_branch" == epic/* ]]; then
        echo "epic:$current_branch"
        return 0
    elif [[ "$current_branch" == */* ]]; then
        echo "feature:$current_branch"
        return 0
    fi
    
    return 1
}

# 处理上下文感知的PR创建
handle_context_pr() {
    local context="$1"
    local target_branch="$2"
    local push_remote="$3"
    local force_mode="${4:-false}"
    
    local context_type="${context%%:*}"
    local branch_name="${context#*:}"
    
    case "$context_type" in
        "feature")
            # 功能分支 → Epic分支
            ui_info "🎯 检测到功能分支上下文: $branch_name"
            local epic_name
            epic_name=$(echo "$branch_name" | cut -d'/' -f1)
            local default_target="epic/$epic_name"
            
            if [[ -z "$target_branch" ]]; then
                target_branch="$default_target"
            fi
            
            ui_info "📋 准备创建PR: $branch_name → $target_branch"
            create_feature_pr "$branch_name" "$target_branch" "$push_remote" "$force_mode"
            ;;
            
        "epic")
            # Epic分支 → develop分支
            ui_info "🎯 检测到Epic分支上下文: $branch_name"
            local default_target="develop"
            
            if [[ -z "$target_branch" ]]; then
                target_branch="$default_target"
            fi
            
            ui_info "📋 准备创建PR: $branch_name → $target_branch"
            create_feature_pr "$branch_name" "$target_branch" "$push_remote" "$force_mode"
            ;;
            
        *)
            ui_error "未知的上下文类型: $context_type"
            return 1
            ;;
    esac
}

# 交互式PR创建处理
handle_pr_interactive() {
    local force_mode="${1:-false}"
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
        create_feature_pr "$selected_feature" "" "" "$force_mode"
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
            worktree_path=$(get_branch_worktree_absolute_path "$branch")
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
    local push_remote="${3:-}"
    local force_mode="${4:-false}"
    
    ui_loading "准备创建PR: $feature_name"
    
    # 验证功能分支存在
    if ! git_branch_exists "$feature_name"; then
        ui_error "功能分支不存在: $feature_name"
        return 1
    fi
    
    # 获取工作树路径
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
    
    if [[ ! -d "$worktree_path" ]]; then
        ui_error "功能分支工作树不存在: $worktree_path"
        ui_info "请先运行: gpf start $feature_name"
        return 1
    fi
    
    # 分析PR上下文
    local pr_context
    pr_context=$(analyze_pr_context "$feature_name")
    
    # 显示PR预览
    show_pr_preview "$feature_name" "$pr_context"
    
    # 智能确认逻辑
    if ! should_auto_create_pr "$feature_name" "$pr_context" "$force_mode"; then
        # 需要确认时才显示确认对话框
        if ! ui_confirm "确认创建PR？"; then
            ui_info "取消PR创建"
            return 1
        fi
    else
        ui_info "✅ 自动创建PR (条件满足，无需确认)"
    fi
    
    # 执行PR创建流程
    execute_pr_creation "$feature_name" "$target_branch" "$pr_context" "$push_remote"
}

# 分析PR上下文
analyze_pr_context() {
    local feature_name="$1"
    local epic_name base_branch
    epic_name=$(config_epic_get "epic_name")
    
    # 智能检测当前环境并获取正确的base_branch
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
    
    if config_feature_exists "$worktree_path"; then
        # 功能分支：使用功能分支配置的base_branch
        base_branch=$(config_feature_get "base_branch" "" "$worktree_path")
    else
        # Epic分支：使用Epic配置的base_branch
        base_branch=$(config_epic_get "base_branch")
    fi
    
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
    "worktree_path": "$(get_branch_worktree_absolute_path "$feature_name")"
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
    
    ui_subheader "最近提交 (前${limit}个)"
    
    # 切换到功能分支工作树
    local worktree_path original_dir
    worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
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
    local push_remote="${4:-}"
    
    ui_loading "🚀 创建PR: $feature_name"
    
    # 确定目标分支 - 智能检测当前环境
    local final_target_branch
    if [[ -n "$target_branch" ]]; then
        final_target_branch="$target_branch"
    else
        # 获取功能分支工作树路径并检测配置类型
        local worktree_path
        worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
        
        # 检查是否存在功能分支配置文件
        if config_feature_exists "$worktree_path"; then
            # 功能分支：使用功能分支配置的base_branch
            final_target_branch=$(config_feature_get "base_branch" "" "$worktree_path")
            ui_info "检测到功能分支环境，目标分支: $final_target_branch"
        else
            # Epic分支：使用Epic配置的base_branch
            final_target_branch=$(config_epic_get "base_branch")
            ui_info "检测到Epic分支环境，目标分支: $final_target_branch"
        fi
        
        # 如果仍然为空，使用默认值
        if [[ -z "$final_target_branch" ]]; then
            final_target_branch="develop"
            ui_warning "无法检测目标分支，使用默认分支: develop"
        fi
    fi
    
    # 切换到功能分支工作树
    local worktree_path original_dir
    worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
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
    
    # 推送分支到远程 - 使用智能推送
    ui_info "📤 推送分支到远程仓库"
    
    # 引入智能推送工具
    source "${PROJECT_ROOT}/lib/utils/smart-push.sh"
    
    if [[ "$push_remote" == "multi-platform" ]]; then
        # 多平台推送模式：分别推送到所有可用的远程平台
        ui_info "🚀 多平台推送模式"
        
        local platform_remotes=()
        local all_remotes
        all_remotes=($(git remote 2>/dev/null || echo ""))
        
        # 自动检测代码托管平台远程
        platform_remotes=($(detect_hosting_platform_remotes))
        
        if [[ ${#platform_remotes[@]} -eq 0 ]]; then
            ui_error "没有找到可用的平台远程"
            cd "$original_dir" || true
            return 1
        fi
        
        ui_info "检测到 ${#platform_remotes[@]} 个平台: ${platform_remotes[*]}"
        
        # 分别推送到每个平台
        local push_success=0
        for remote in "${platform_remotes[@]}"; do
            ui_info "📤 推送到 $remote"
            if smart_push_to_remote "$feature_name" "$remote" "false" "false"; then
                ui_success "✅ $remote 推送成功"
                ((push_success++))
            else
                ui_warning "❌ $remote 推送失败"
            fi
        done
        
        if [[ $push_success -eq 0 ]]; then
            ui_error "所有平台推送都失败"
            cd "$original_dir" || true
            return 1
        fi
        
        ui_success "🎉 成功推送到 $push_success/${#platform_remotes[@]} 个平台"
        
    elif [[ -n "$push_remote" ]]; then
        # 使用指定的远程推送
        ui_info "使用指定远程: $push_remote"
        if ! smart_push_to_remote "$feature_name" "$push_remote" "false" "true"; then
            ui_warning "常规推送失败，尝试强制推送"
            if ! smart_push_to_remote "$feature_name" "$push_remote" "true" "true"; then
                ui_error "无法推送分支到远程: $push_remote"
                cd "$original_dir" || true
                return 1
            fi
        fi
    else
        # 使用智能推送
        if ! smart_push_branch "$feature_name" "false" "true"; then
            ui_warning "常规推送失败，尝试强制推送"
            if ! smart_push_branch "$feature_name" "true" "true"; then
                ui_error "无法推送分支到远程"
                ui_info "运行 'gpf push --diagnose' 获取详细诊断"
                cd "$original_dir" || true
                return 1
            fi
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

# 显示PR命令帮助信息
show_pr_help() {
    cat << EOF
GPF PR命令 - 智能PR创建工具

用法:
  gpf pr [选项] [功能名称] [目标分支]

选项:
  --push-remote <remote>    指定推送的远程仓库
  --multi-platform          推送到所有配置的平台（github, gitee等）
  --target <branch>         指定目标分支
  --force                   强制跳过所有确认（适用于自动化脚本）
  --help, -h                显示此帮助信息

参数:
  功能名称                  要创建PR的功能分支名称
  目标分支                  PR的目标分支（默认为Epic基础分支）

功能:
  - 智能检测Git配置并适配不同的远程仓库设置
  - 自动生成PR标题和描述
  - 支持Epic上下文和依赖关系分析
  - 提供详细的推送错误诊断和解决建议

示例:
  gpf pr feature-name                        # 创建PR，自动检测推送目标（优先all远程）
  gpf pr feature-name --push-remote github   # 指定推送到github远程
  gpf pr feature-name --multi-platform       # 推送到所有平台（github + gitee）
  gpf pr feature-name --push-remote all      # 使用all远程同时推送多平台
  gpf pr feature-name develop                # 指定目标分支为develop

推送失败时的解决方案:
  1. 查看配置分析: gpf push --diagnose
  2. 手动指定远程: gpf pr --push-remote <remote> <feature>
  3. 原生Git推送: git push <remote> <branch>

EOF
}

# 智能确认逻辑 - 决定是否需要用户确认
should_auto_create_pr() {
    local feature_name="$1"
    local pr_context="$2"
    local force_mode="${3:-false}"
    
    # 强制模式：直接跳过所有确认
    if [[ "$force_mode" == "true" ]]; then
        ui_info "🚀 强制模式：跳过所有确认"
        return 0
    fi
    
    # 获取工作树路径检查风险条件
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
    
    local risk_issues=()
    local safety_checks_passed=true
    
    # 安全检查1: 检查工作目录是否干净
    if [[ -d "$worktree_path" ]]; then
        local original_dir
        original_dir=$(pwd)
        cd "$worktree_path" || return 1
        
        if ! git_is_clean; then
            risk_issues+=("工作目录有未提交的变更")
            safety_checks_passed=false
        fi
        
        cd "$original_dir" || true
    fi
    
    # 安全检查2: 检查是否有足够的提交
    local commit_count
    commit_count=$(echo "$pr_context" | grep '"commit_count"' | cut -d':' -f2 | cut -d',' -f1 | tr -d ' ')
    
    if [[ "$commit_count" -eq 0 ]]; then
        risk_issues+=("分支没有提交")
        safety_checks_passed=false
    fi
    
    # 安全检查3: 检查是否在正确的上下文环境中
    local current_context
    current_context=$(detect_pr_context)
    
    if [[ -z "$current_context" ]]; then
        risk_issues+=("无法检测当前环境上下文")
        safety_checks_passed=false
    fi
    
    # 安全检查4: 检查是否有明显的分支冲突风险
    local base_branch
    base_branch=$(echo "$pr_context" | grep '"base_branch"' | cut -d'"' -f4)
    
    if [[ -n "$base_branch" ]]; then
        # 检查是否存在分支分歧 (这是一个简化的检查)
        local diverged_commits
        diverged_commits=$(git rev-list --count "$base_branch..$feature_name" 2>/dev/null || echo "0")
        
        # 如果分支有很多新提交，可能需要用户确认
        if [[ "$diverged_commits" -gt 20 ]]; then
            risk_issues+=("分支有较多新提交($diverged_commits个)，可能需要rebase")
        fi
    fi
    
    # 条件判断：是否应该自动创建PR
    local auto_create_conditions=()
    
    # 条件1: 在功能分支目录中
    local current_dir=$(pwd)
    if [[ "$current_dir" == *"/.worktrees/epic--"*"--"* ]]; then
        auto_create_conditions+=("在功能分支工作目录中")
    fi
    
    # 条件2: 参数完整 (feature_name存在且有效)
    if [[ -n "$feature_name" && -d "$worktree_path" ]]; then
        auto_create_conditions+=("参数完整且分支有效")
    fi
    
    # 条件3: 上下文清晰 (能够自动检测到正确的上下文)
    if [[ -n "$current_context" ]]; then
        auto_create_conditions+=("上下文检测清晰")
    fi
    
    # 最终决策逻辑
    if [[ "$safety_checks_passed" == "true" && ${#auto_create_conditions[@]} -ge 2 ]]; then
        # 安全检查通过且满足至少2个自动创建条件
        ui_info "🔍 自动创建条件检查："
        for condition in "${auto_create_conditions[@]}"; do
            ui_info "  ✅ $condition"
        done
        return 0  # 可以自动创建
    else
        # 存在风险或条件不足，需要用户确认
        if [[ ${#risk_issues[@]} -gt 0 ]]; then
            ui_warning "⚠️ 检测到以下风险，需要用户确认："
            for issue in "${risk_issues[@]}"; do
                ui_warning "  ❌ $issue"
            done
        fi
        
        if [[ ${#auto_create_conditions[@]} -lt 2 ]]; then
            ui_info "💡 自动创建条件不足 (${#auto_create_conditions[@]}/2)："
            if [[ ${#auto_create_conditions[@]} -gt 0 ]]; then
                for condition in "${auto_create_conditions[@]}"; do
                    ui_info "  ✅ $condition"
                done
            fi
            ui_info "  💡 提示：在功能分支目录中运行命令可减少确认步骤"
        fi
        
        return 1  # 需要用户确认
    fi
}