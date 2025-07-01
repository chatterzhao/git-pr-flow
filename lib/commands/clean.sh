#!/usr/bin/env bash

# Git PR Flow - clean命令实现
# 智能环境清理，支持工作树、分支、Epic级清理
# safety-check-system: 全面的安全检查机制

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# ====== 安全检查系统核心函数 ======

# 执行全面安全检查
perform_comprehensive_safety_check() {
    local check_target="${1:-all}"  # all, worktrees, branches, epic
    local target_name="${2:-}"      # 具体目标名称（如epic名称）
    local force_mode="${3:-false}"  # 是否强制模式
    
    ui_header "🔍 安全检查系统"
    
    local safety_result
    safety_result=$(create_safety_check_result)
    
    # 执行各项检查
    check_uncommitted_changes "$safety_result" "$check_target" "$target_name"
    check_unmerged_branches "$safety_result" "$check_target" "$target_name"
    check_unpushed_commits "$safety_result" "$check_target" "$target_name"
    check_active_worktrees "$safety_result" "$check_target" "$target_name"
    check_branch_dependencies "$safety_result" "$check_target" "$target_name"
    
    # 显示检查结果
    display_safety_check_results "$safety_result" "$force_mode"
    
    # 返回检查结果（0=安全，1=警告，2=阻断）
    get_safety_check_level "$safety_result"
}

# 创建安全检查结果结构
create_safety_check_result() {
    cat << 'EOF'
{
    "safe_items": [],
    "warning_items": [],
    "blocking_items": [],
    "recommendations": []
}
EOF
}

# 检查未提交更改
check_uncommitted_changes() {
    local safety_result="$1"
    local check_target="$2"
    local target_name="$3"
    
    ui_loading "检查未提交更改..."
    
    local uncommitted_worktrees=()
    local main_repo_status=""
    
    # 检查主仓库
    if ! git diff-index --quiet HEAD 2>/dev/null || ! git diff-index --cached --quiet HEAD 2>/dev/null; then
        main_repo_status="主仓库有未提交更改"
        add_blocking_item "$safety_result" "main_repo_uncommitted" "$main_repo_status" \
            "git add . && git commit -m \"保存更改\"" \
            "或: git stash save \"临时保存\""
    fi
    
    # 检查工作树
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                local original_dir=$(pwd)
                
                cd "$worktree" 2>/dev/null || continue
                
                # 检查是否有未提交更改
                local has_changes=false
                if ! git diff-index --quiet HEAD 2>/dev/null; then
                    has_changes=true
                elif ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                    has_changes=true
                elif [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                    has_changes=true
                fi
                
                if [[ "$has_changes" == "true" ]]; then
                    local branch_name
                    branch_name=$(git branch --show-current 2>/dev/null || echo "unknown")
                    
                    add_blocking_item "$safety_result" "worktree_uncommitted_$worktree_name" \
                        "工作树 $worktree_name ($branch_name) 有未提交更改" \
                        "cd \"$worktree\" && git add . && git commit -m \"保存更改\"" \
                        "或: cd \"$worktree\" && git stash save \"临时保存\""
                fi
                
                cd "$original_dir" || true
            fi
        done
    fi
    
    echo "✅ 未提交更改检查完成"
}

# 检查未合并分支
check_unmerged_branches() {
    local safety_result="$1"
    local check_target="$2"
    local target_name="$3"
    
    ui_loading "检查未合并分支..."
    
    # 获取主要分支
    local main_branches=("main" "master" "develop")
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)
    
    # 检查未合并到主分支的分支
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local unmerged_branches
            unmerged_branches=$(git branch --no-merged "$main_branch" 2>/dev/null | grep -v "^\*" | sed 's/^[+ ]*//' || true)
            
            while IFS= read -r branch; do
                if [[ -n "$branch" && "$branch" != "$current_branch" ]]; then
                    # 排除主要分支
                    local is_main=false
                    for mb in "${main_branches[@]}"; do
                        if [[ "$branch" == "$mb" ]]; then
                            is_main=true
                            break
                        fi
                    done
                    
                    if [[ "$is_main" == "false" ]]; then
                        # 检查是否有未推送的提交
                        local commits_ahead=0
                        if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                            commits_ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
                        fi
                        
                        if [[ "$commits_ahead" -gt 0 ]]; then
                            add_warning_item "$safety_result" "unmerged_branch_$branch" \
                                "分支 $branch 未合并到 $main_branch，且有 $commits_ahead 个未推送提交" \
                                "git checkout $main_branch && git merge $branch" \
                                "或: git push origin $branch 然后通过PR合并"
                        else
                            add_warning_item "$safety_result" "unmerged_branch_$branch" \
                                "分支 $branch 未合并到 $main_branch" \
                                "git checkout $main_branch && git merge $branch" \
                                "或: 通过PR将分支合并到主分支"
                        fi
                    fi
                fi
            done <<< "$unmerged_branches"
            break  # 只需要检查一个存在的主分支
        fi
    done
    
    echo "✅ 未合并分支检查完成"
}

# 检查未推送提交
check_unpushed_commits() {
    local safety_result="$1"
    local check_target="$2"
    local target_name="$3"
    
    ui_loading "检查未推送提交..."
    
    # 检查当前分支的未推送提交
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)
    
    if [[ -n "$current_branch" ]]; then
        local remote_branch="origin/$current_branch"
        if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
            local commits_ahead
            commits_ahead=$(git rev-list --count "$remote_branch..HEAD" 2>/dev/null || echo "0")
            
            if [[ "$commits_ahead" -gt 0 ]]; then
                add_warning_item "$safety_result" "unpushed_commits_current" \
                    "当前分支 $current_branch 有 $commits_ahead 个未推送提交" \
                    "git push origin $current_branch" \
                    "或: git push origin $current_branch --force-with-lease (如果需要强制推送)"
            fi
        else
            # 远程分支不存在
            local local_commits
            local_commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")
            if [[ "$local_commits" -gt 0 ]]; then
                add_warning_item "$safety_result" "unpushed_new_branch" \
                    "新分支 $current_branch 尚未推送到远程 ($local_commits 个提交)" \
                    "git push origin $current_branch" \
                    "或: git push origin $current_branch --set-upstream"
            fi
        fi
    fi
    
    # 检查工作树中的未推送提交
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                local original_dir=$(pwd)
                
                cd "$worktree" 2>/dev/null || continue
                
                local branch_name
                branch_name=$(git branch --show-current 2>/dev/null || echo "")
                
                if [[ -n "$branch_name" ]]; then
                    local remote_branch="origin/$branch_name"
                    if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
                        local commits_ahead
                        commits_ahead=$(git rev-list --count "$remote_branch..HEAD" 2>/dev/null || echo "0")
                        
                        if [[ "$commits_ahead" -gt 0 ]]; then
                            add_warning_item "$safety_result" "unpushed_commits_$worktree_name" \
                                "工作树 $worktree_name ($branch_name) 有 $commits_ahead 个未推送提交" \
                                "cd \"$worktree\" && git push origin $branch_name" \
                                "或: 切换到工作树后推送"
                        fi
                    fi
                fi
                
                cd "$original_dir" || true
            fi
        done
    fi
    
    echo "✅ 未推送提交检查完成"
}

# 检查活跃工作树
check_active_worktrees() {
    local safety_result="$1"
    local check_target="$2"
    local target_name="$3"
    
    ui_loading "检查活跃工作树..."
    
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                local original_dir=$(pwd)
                
                cd "$worktree" 2>/dev/null || continue
                
                local branch_name
                branch_name=$(git branch --show-current 2>/dev/null || echo "")
                
                # 检查是否有进行中的操作
                local is_active=false
                local activity_reason=""
                
                # 检查是否在进行merge
                if [[ -f ".git/MERGE_HEAD" ]]; then
                    is_active=true
                    activity_reason="正在进行合并操作"
                # 检查是否在进行rebase
                elif [[ -d ".git/rebase-merge" || -d ".git/rebase-apply" ]]; then
                    is_active=true
                    activity_reason="正在进行变基操作"
                # 检查是否有未提交的更改
                elif ! git diff-index --quiet HEAD 2>/dev/null || ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                    is_active=true
                    activity_reason="有未提交的更改"
                fi
                
                if [[ "$is_active" == "true" ]]; then
                    add_blocking_item "$safety_result" "active_worktree_$worktree_name" \
                        "工作树 $worktree_name ($branch_name) 正在活跃使用: $activity_reason" \
                        "cd \"$worktree\" && 完成当前操作后再清理" \
                        "或: 使用 --force 强制清理（可能丢失数据）"
                else
                    add_safe_item "$safety_result" "inactive_worktree_$worktree_name" \
                        "工作树 $worktree_name ($branch_name) 可以安全清理"
                fi
                
                cd "$original_dir" || true
            fi
        done
    fi
    
    echo "✅ 活跃工作树检查完成"
}

# 检查分支依赖关系
check_branch_dependencies() {
    local safety_result="$1"
    local check_target="$2"
    local target_name="$3"
    
    ui_loading "检查分支依赖关系..."
    
    # 如果是清理特定Epic，检查该Epic的依赖
    if [[ "$check_target" == "epic" && -n "$target_name" ]]; then
        local epic_branches
        epic_branches=$(git branch --format='%(refname:short)' | grep "^$target_name/" || true)
        
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                # 检查是否有其他分支依赖这个分支
                local dependent_branches
                dependent_branches=$(git branch --format='%(refname:short)' | while read -r other_branch; do
                    if [[ "$other_branch" != "$branch" && -n "$other_branch" ]]; then
                        # 检查是否 other_branch 是基于 branch 创建的
                        if git merge-base --is-ancestor "$branch" "$other_branch" 2>/dev/null; then
                            echo "$other_branch"
                        fi
                    fi
                done)
                
                if [[ -n "$dependent_branches" ]]; then
                    add_warning_item "$safety_result" "branch_dependency_$branch" \
                        "分支 $branch 被其他分支依赖: $(echo "$dependent_branches" | tr '\n' ' ')" \
                        "先处理依赖分支，或确认清理不会影响其他开发" \
                        "或: 使用 --force 忽略依赖关系"
                fi
            fi
        done <<< "$epic_branches"
    fi
    
    echo "✅ 分支依赖关系检查完成"
}

# 添加安全项目
add_safe_item() {
    local safety_result="$1"
    local item_id="$2"
    local description="$3"
    
    # 这里实际上应该修改safety_result，但为了简化，我们用全局变量
    SAFE_ITEMS+=("$item_id|$description")
}

# 添加警告项目
add_warning_item() {
    local safety_result="$1"
    local item_id="$2"
    local description="$3"
    local solution1="$4"
    local solution2="${5:-}"
    
    WARNING_ITEMS+=("$item_id|$description|$solution1|$solution2")
}

# 添加阻断项目
add_blocking_item() {
    local safety_result="$1"
    local item_id="$2"
    local description="$3"
    local solution1="$4"
    local solution2="${5:-}"
    
    BLOCKING_ITEMS+=("$item_id|$description|$solution1|$solution2")
}

# 显示安全检查结果
display_safety_check_results() {
    local safety_result="$1"
    local force_mode="$2"
    
    echo
    ui_subheader "📊 安全检查结果"
    
    # 显示安全项目
    if [[ ${#SAFE_ITEMS[@]} -gt 0 ]]; then
        echo
        ui_success "🟢 安全项目 (${#SAFE_ITEMS[@]} 项):"
        for item in "${SAFE_ITEMS[@]}"; do
            local description=$(echo "$item" | cut -d'|' -f2)
            echo "  ✅ $description"
        done
    fi
    
    # 显示警告项目
    if [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
        echo
        ui_warning "🟡 警告项目 (${#WARNING_ITEMS[@]} 项):"
        for item in "${WARNING_ITEMS[@]}"; do
            local description=$(echo "$item" | cut -d'|' -f2)
            local solution1=$(echo "$item" | cut -d'|' -f3)
            local solution2=$(echo "$item" | cut -d'|' -f4)
            
            echo "  ⚠️ $description"
            echo "    💡 解决方案:"
            echo "       $solution1"
            if [[ -n "$solution2" ]]; then
                echo "       $solution2"
            fi
        done
    fi
    
    # 显示阻断项目
    if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
        echo
        ui_error "🔴 阻断项目 (${#BLOCKING_ITEMS[@]} 项):"
        for item in "${BLOCKING_ITEMS[@]}"; do
            local description=$(echo "$item" | cut -d'|' -f2)
            local solution1=$(echo "$item" | cut -d'|' -f3)
            local solution2=$(echo "$item" | cut -d'|' -f4)
            
            echo "  ❌ $description"
            echo "    💡 解决方案:"
            echo "       $solution1"
            if [[ -n "$solution2" ]]; then
                echo "       $solution2"
            fi
        done
    fi
    
    # 显示总结和建议
    echo
    display_safety_summary "$force_mode"
}

# 显示安全检查总结
display_safety_summary() {
    local force_mode="$1"
    
    local safe_count=${#SAFE_ITEMS[@]}
    local warning_count=${#WARNING_ITEMS[@]}
    local blocking_count=${#BLOCKING_ITEMS[@]}
    
    ui_subheader "📋 检查总结"
    
    if [[ $blocking_count -gt 0 ]]; then
        ui_error "❌ 存在 $blocking_count 个阻断条件，无法安全执行清理"
        if [[ "$force_mode" == "true" ]]; then
            ui_warning "⚠️ 强制模式已启用，将跳过所有检查"
        else
            ui_info "💡 建议："
            ui_info "  1. 解决上述阻断问题后重试"
            ui_info "  2. 使用 --force 强制清理（可能导致数据丢失）"
        fi
    elif [[ $warning_count -gt 0 ]]; then
        ui_warning "⚠️ 存在 $warning_count 个警告项目，建议谨慎操作"
        ui_info "💡 建议："
        ui_info "  1. 解决警告问题后重试以获得最佳安全性"
        ui_info "  2. 继续执行清理（会保留警告项目）"
    else
        ui_success "✅ 所有检查通过，可以安全执行清理"
    fi
    
    if [[ $safe_count -gt 0 ]]; then
        ui_success "🟢 可以安全清理 $safe_count 项资源"
    fi
}

# 获取安全检查级别
get_safety_check_level() {
    local safety_result="$1"
    
    if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
        return 2  # 阻断
    elif [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
        return 1  # 警告
    else
        return 0  # 安全
    fi
}

# 全局数组用于存储检查结果
declare -a SAFE_ITEMS=()
declare -a WARNING_ITEMS=()
declare -a BLOCKING_ITEMS=()

# clean命令主函数 - 集成安全检查系统
cmd_clean() {
    local dry_run=false
    local force_mode=false
    local safety_check=true
    local help_mode=false
    local scope=""
    local target=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force_mode=true
                shift
                ;;
            --no-safety-check)
                safety_check=false
                shift
                ;;
            --help|-h)
                help_mode=true
                shift
                ;;
            --all)
                scope="all"
                shift
                ;;
            --release)
                scope="release"
                shift
                ;;
            worktrees|branches|epic|merged)
                if [[ -z "$scope" ]]; then
                    scope="$1"
                    shift
                    # 下一个参数可能是target
                    if [[ $# -gt 0 && "$1" != -* ]]; then
                        target="$1"
                        shift
                    fi
                else
                    ui_error "不能同时指定多个清理类型"
                    return 1
                fi
                ;;
            -*)
                ui_error "未知选项: $1"
                show_safety_clean_help
                return 1
                ;;
            *)
                if [[ -z "$scope" ]]; then
                    ui_error "无效的清理类型: $1"
                    show_safety_clean_help
                    return 1
                elif [[ -z "$target" ]]; then
                    target="$1"
                    shift
                else
                    ui_error "过多参数: $1"
                    return 1
                fi
                ;;
        esac
    done
    
    # 显示帮助信息
    if [[ "$help_mode" == "true" ]]; then
        show_safety_clean_help
        return 0
    fi
    
    # 处理只有 --dry-run 参数的情况
    if [[ -z "$scope" && "$dry_run" == "true" ]]; then
        perform_comprehensive_safety_check "all" "" "$force_mode"
        return $?
    fi
    
    # 无参数时显示安全检查报告
    if [[ -z "$scope" ]]; then
        perform_comprehensive_safety_check "all" "" "$force_mode"
        show_safety_guided_options
        return 0
    fi
    
    # 执行安全检查（除非明确跳过）
    local safety_level=0
    if [[ "$safety_check" == "true" && "$force_mode" == "false" ]]; then
        perform_comprehensive_safety_check "$scope" "$target" "$force_mode"
        safety_level=$?
        
        # 如果有阻断条件，停止执行
        if [[ $safety_level -eq 2 ]]; then
            ui_error "❌ 安全检查发现阻断条件，停止执行"
            ui_info "💡 使用 --force 强制执行或解决上述问题后重试"
            return 1
        elif [[ $safety_level -eq 1 ]]; then
            ui_warning "⚠️ 安全检查发现警告项目"
            if ! ui_confirm "继续执行清理？"; then
                ui_info "取消清理操作"
                return 0
            fi
        fi
    fi
    
    # 执行相应的清理操作
    case "$scope" in
        "worktrees")
            if [[ "$dry_run" == "true" ]]; then
                preview_clean_worktrees "$target"
            else
                clean_worktrees_with_safety "$target" "$force_mode"
            fi
            ;;
        "branches")
            if [[ "$dry_run" == "true" ]]; then
                preview_clean_branches "$target"
            else
                clean_branches_with_safety "$target" "$force_mode"
            fi
            ;;
        "epic")
            if [[ -z "$target" ]]; then
                ui_error "清理Epic需要指定Epic名称"
                ui_info "用法: gpf clean epic <epic-name>"
                return 1
            fi
            if [[ "$dry_run" == "true" ]]; then
                preview_clean_epic "$target"
            else
                clean_epic_with_safety "$target" "$force_mode"
            fi
            ;;
        "merged")
            if [[ "$dry_run" == "true" ]]; then
                preview_clean_merged_branches
            else
                clean_merged_branches_with_safety "$force_mode"
            fi
            ;;
        "all")
            if [[ "$dry_run" == "true" ]]; then
                preview_clean_all
            else
                clean_all_with_safety "$force_mode"
            fi
            ;;
        "release")
            clean_after_release_with_safety "$force_mode"
            ;;
        *)
            # 这应该不会到达，因为参数解析已经处理了
            handle_clean_interactive_with_safety
            ;;
    esac
}

# ====== 安全检查集成的新功能函数 ======

# 显示安全检查帮助信息
show_safety_clean_help() {
    cat << EOF
GPF Clean命令 - 智能环境清理工具（集成安全检查系统）

用法:
  gpf clean [选项] [类型] [目标]

选项:
  --dry-run             预览清理计划和安全检查，不执行实际操作
  --all                 清理所有类型的资源
  --force               强制清理，跳过安全检查
  --no-safety-check     跳过安全检查（不推荐）
  --help, -h            显示此帮助信息

清理类型:
  worktrees [pattern]   清理工作树（pattern可选，支持通配符）
  branches [pattern]    清理分支（pattern可选，支持通配符）
  epic <epic-name>      清理指定Epic（必须指定Epic名称）
  merged                清理已合并分支

特殊操作:
  --release             发布后清理

示例:
  gpf clean                           # 显示全面安全检查和引导
  gpf clean --dry-run                 # 预览所有清理计划和安全检查
  gpf clean --all                     # 安全清理所有资源（含安全检查）
  gpf clean --all --force             # 强制清理所有资源（跳过安全检查）
  gpf clean worktrees                 # 清理工作树（含安全检查）
  gpf clean branches feature/*        # 清理feature分支（含安全检查）
  gpf clean epic test                 # 清理test Epic（含安全检查）

安全检查级别:
  🟢 安全操作：通过所有检查的清理操作
  🟡 警告操作：有警告但可以继续的操作
  🔴 阻断操作：存在风险，需要解决问题或使用 --force

安全检查内容:
  - 未提交更改检查（git status）
  - 未合并分支检查（git branch --no-merged）
  - 未推送提交检查（git log @{u}..HEAD）
  - 活跃工作树检查（正在使用的分支）
  - 分支依赖关系检查

EOF
}

# 显示安全引导选项
show_safety_guided_options() {
    echo
    ui_subheader "💡 根据安全检查结果的推荐操作"
    
    local safe_count=${#SAFE_ITEMS[@]}
    local warning_count=${#WARNING_ITEMS[@]}
    local blocking_count=${#BLOCKING_ITEMS[@]}
    
    if [[ $blocking_count -eq 0 && $warning_count -eq 0 && $safe_count -gt 0 ]]; then
        echo
        ui_success "✅ 环境安全，推荐执行："
        ui_info "  gpf clean --all                     # 安全清理所有资源"
        ui_info "  gpf clean worktrees                 # 只清理工作树"
        ui_info "  gpf clean branches                  # 只清理已合并分支"
        
    elif [[ $blocking_count -eq 0 && $warning_count -gt 0 ]]; then
        echo
        ui_warning "⚠️ 存在警告项目，建议操作："
        ui_info "  1. 先解决警告问题（推荐）："
        for item in "${WARNING_ITEMS[@]}"; do
            local solution1=$(echo "$item" | cut -d'|' -f3)
            ui_info "     $solution1"
        done
        echo
        ui_info "  2. 或谨慎执行清理："
        ui_info "     gpf clean --all                  # 继续清理（会提示确认）"
        
    elif [[ $blocking_count -gt 0 ]]; then
        echo
        ui_error "🔴 存在阻断条件，需要先解决："
        for item in "${BLOCKING_ITEMS[@]}"; do
            local solution1=$(echo "$item" | cut -d'|' -f3)
            ui_info "  $solution1"
        done
        echo
        ui_info "解决后重试："
        ui_info "  gpf clean --all                     # 重新检查并清理"
        echo
        ui_info "强制清理（可能丢失数据）："
        ui_info "  gpf clean --all --force             # 跳过所有安全检查"
        
    else
        echo
        ui_info "🧹 常用清理操作："
        ui_info "  gpf clean --dry-run                 # 预览清理计划"
        ui_info "  gpf clean --all                     # 全面清理"
        ui_info "  gpf clean worktrees                 # 清理工作树"
        ui_info "  gpf clean branches                  # 清理分支"
    fi
    
    echo
    ui_info "📖 详细帮助：gpf clean --help"
}

# 带安全检查的工作树清理
clean_worktrees_with_safety() {
    local target_pattern="$1"
    local force_mode="$2"
    
    ui_subheader "🧹 安全工作树清理"
    
    # 如果不是强制模式，进行额外的工作树特定检查
    if [[ "$force_mode" != "true" ]]; then
        ui_info "执行工作树特定安全检查..."
        
        # 重置检查结果数组
        SAFE_ITEMS=()
        WARNING_ITEMS=()
        BLOCKING_ITEMS=()
        
        # 只检查工作树相关的安全项
        check_uncommitted_changes "" "worktrees" "$target_pattern"
        check_active_worktrees "" "worktrees" "$target_pattern"
        
        # 如果有阻断条件，停止
        if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
            display_safety_check_results "" "$force_mode"
            return 1
        fi
    fi
    
    # 调用原始的清理函数
    clean_worktrees "$target_pattern"
}

# 带安全检查的分支清理
clean_branches_with_safety() {
    local target_pattern="$1"
    local force_mode="$2"
    
    ui_subheader "🌿 安全分支清理"
    
    # 如果不是强制模式，进行额外的分支特定检查
    if [[ "$force_mode" != "true" ]]; then
        ui_info "执行分支特定安全检查..."
        
        # 重置检查结果数组
        SAFE_ITEMS=()
        WARNING_ITEMS=()
        BLOCKING_ITEMS=()
        
        # 只检查分支相关的安全项
        check_unmerged_branches "" "branches" "$target_pattern"
        check_unpushed_commits "" "branches" "$target_pattern"
        
        # 显示检查结果
        if [[ ${#WARNING_ITEMS[@]} -gt 0 || ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
            display_safety_check_results "" "$force_mode"
            
            if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
                return 1
            fi
            
            if [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
                if ! ui_confirm "存在警告项目，继续清理分支？"; then
                    ui_info "取消分支清理"
                    return 0
                fi
            fi
        fi
    fi
    
    # 调用原始的清理函数
    clean_branches "$target_pattern"
}

# 带安全检查的Epic清理
clean_epic_with_safety() {
    local epic_name="$1"
    local force_mode="$2"
    
    ui_subheader "🚀 安全Epic清理"
    
    # 如果不是强制模式，进行Epic特定检查
    if [[ "$force_mode" != "true" ]]; then
        ui_info "执行Epic特定安全检查..."
        
        # 重置检查结果数组
        SAFE_ITEMS=()
        WARNING_ITEMS=()
        BLOCKING_ITEMS=()
        
        # 执行Epic相关的所有检查
        check_uncommitted_changes "" "epic" "$epic_name"
        check_unmerged_branches "" "epic" "$epic_name"
        check_unpushed_commits "" "epic" "$epic_name"
        check_active_worktrees "" "epic" "$epic_name"
        check_branch_dependencies "" "epic" "$epic_name"
        
        # 显示检查结果并确认
        if [[ ${#WARNING_ITEMS[@]} -gt 0 || ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
            display_safety_check_results "" "$force_mode"
            
            if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
                return 1
            fi
            
            if [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
                ui_warning "⚠️ Epic清理是高风险操作"
                if ! ui_confirm "确认清理整个Epic '$epic_name'？"; then
                    ui_info "取消Epic清理"
                    return 0
                fi
            fi
        fi
    fi
    
    # 调用原始的清理函数
    clean_epic "$epic_name"
}

# 带安全检查的已合并分支清理
clean_merged_branches_with_safety() {
    local force_mode="$1"
    
    ui_subheader "🌿 安全已合并分支清理"
    
    # 已合并分支清理相对安全，只进行基本检查
    if [[ "$force_mode" != "true" ]]; then
        ui_info "执行已合并分支安全检查..."
        
        # 重置检查结果数组
        SAFE_ITEMS=()
        WARNING_ITEMS=()
        BLOCKING_ITEMS=()
        
        # 检查未推送提交（已合并但可能有本地修改）
        check_unpushed_commits "" "merged" ""
        
        if [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
            display_safety_check_results "" "$force_mode"
            if ! ui_confirm "继续清理已合并分支？"; then
                ui_info "取消已合并分支清理"
                return 0
            fi
        fi
    fi
    
    # 调用原始的清理函数
    clean_merged_branches
}

# 带安全检查的全面清理
clean_all_with_safety() {
    local force_mode="$1"
    
    ui_subheader "🧹 安全全面清理"
    
    if [[ "$force_mode" != "true" ]]; then
        ui_warning "⚠️ 全面清理是高风险操作，已执行完整安全检查"
        ui_info "如果需要强制清理，请使用: gpf clean --all --force"
        
        # 安全检查已在主函数中执行，这里只需要最终确认
        if ! ui_confirm "确认执行全面清理？"; then
            ui_info "取消全面清理"
            return 0
        fi
    else
        ui_warning "⚠️ 强制模式：跳过所有安全检查"
        if ! ui_confirm "确认强制执行全面清理？这可能导致数据丢失"; then
            ui_info "取消强制清理"
            return 0
        fi
    fi
    
    # 调用原始的全面清理函数
    clean_all_with_confirmation
}

# 带安全检查的发布后清理
clean_after_release_with_safety() {
    local force_mode="$1"
    
    ui_subheader "🎉 安全发布后清理"
    
    # 发布后清理相对安全，但仍需要基本检查
    if [[ "$force_mode" != "true" ]]; then
        ui_info "执行发布后清理安全检查..."
        
        # 重置检查结果数组
        SAFE_ITEMS=()
        WARNING_ITEMS=()
        BLOCKING_ITEMS=()
        
        # 基本的安全检查
        check_uncommitted_changes "" "release" ""
        check_active_worktrees "" "release" ""
        
        if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
            display_safety_check_results "" "$force_mode"
            return 1
        fi
    fi
    
    # 调用原始的发布后清理函数
    clean_after_release
}

# 带安全检查的交互式清理
handle_clean_interactive_with_safety() {
    # 先执行全面安全检查
    ui_header "🔍 智能环境清理（安全模式）"
    
    perform_comprehensive_safety_check "all" "" "false"
    show_safety_guided_options
    
    # 然后显示交互式选项
    handle_clean_interactive
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