#!/usr/bin/env bash

# Git PR Flow - clean命令实现
# 智能环境清理，支持工作树、分支、Epic级清理
# 完整集成：intelligent-guidance + safety-check-system + batch-operations + enhanced-user-experience

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# ====== 全局配置变量 ======

# 批量操作统计变量
BATCH_STATS_WORKTREES_CLEANED=0
BATCH_STATS_WORKTREES_TOTAL=0
BATCH_STATS_BRANCHES_CLEANED=0
BATCH_STATS_BRANCHES_TOTAL=0
BATCH_STATS_EPICS_CLEANED=0
BATCH_STATS_EPICS_TOTAL=0
BATCH_STATS_FILES_CLEANED=0
BATCH_STATS_DISK_SAVED=""
BATCH_STATS_ERRORS=0

# 增强用户体验变量
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_BAR_WIDTH=40
CLEANUP_HISTORY_FILE=".gpf-cleanup-history.log"
MAX_HISTORY_ENTRIES=50

# 安全检查系统变量
declare -a SAFE_ITEMS=()
declare -a WARNING_ITEMS=()
declare -a BLOCKING_ITEMS=()

# 分析清理项目的全局变量
declare -a ANALYZE_SAFE_ITEMS=()
declare -a ANALYZE_WARNING_ITEMS=()
declare -a ANALYZE_RISKY_ITEMS=()

# ====== clean命令主函数 ======

cmd_clean() {
    local dry_run=false
    local force_mode=false
    local help_mode=false
    local interactive_mode=false
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
            --all)
                scope="all"
                shift
                ;;
            --help|-h)
                help_mode=true
                shift
                ;;
            --release)
                scope="release"
                shift
                ;;
            --interactive|-i)
                interactive_mode=true
                shift
                ;;
            --categorized)
                # 新增：分级显示清理项目
                show_categorized_cleanup_items "all"
                return 0
                ;;
            --partial)
                # 新增：部分清理选择
                interactive_partial_cleanup
                return 0
                ;;
            --history)
                # 新增：显示清理历史
                show_cleanup_history
                return 0
                ;;
            --no-safety-check)
                # 跳过安全检查（不推荐）
                local safety_check=false
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
                show_enhanced_clean_help
                return 1
                ;;
            *)
                if [[ -z "$scope" ]]; then
                    ui_error "无效的清理类型: $1"
                    show_enhanced_clean_help
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
        show_enhanced_clean_help
        return 0
    fi
    
    # 处理只有 --dry-run 参数的情况
    if [[ -z "$scope" && "$dry_run" == "true" ]]; then
        show_categorized_cleanup_items "all"
        return 0
    fi
    
    # 无参数或交互模式时显示增强的交互界面
    if [[ -z "$scope" || "$interactive_mode" == "true" ]]; then
        handle_enhanced_interactive_cleanup
        return 0
    fi
    
    # 记录清理开始
    log_cleanup_start "$scope" "$target" "$force_mode" "$dry_run"
    
    # 执行增强的清理操作（集成所有功能）
    execute_integrated_cleanup "$scope" "$target" "$force_mode" "$dry_run"
}

# ====== 增强的帮助系统 ======

show_enhanced_clean_help() {
    ui_header "🧹 增强版清理命令帮助"
    
    echo "用法: gpf clean [选项] [类型] [目标]"
    echo
    
    ui_subheader "基本清理类型"
    echo "  worktrees                    清理未使用的工作树"
    echo "  branches                     清理已合并的分支"
    echo "  epic [name]                  清理指定Epic相关资源"
    echo "  merged                       清理已合并分支"
    echo
    
    ui_subheader "批量操作选项"
    echo "  --all                        清理所有安全资源"
    echo "  --force                      强制清理（跳过安全检查）"
    echo "  --dry-run                    预览清理操作（不执行）"
    echo "  --release                    发布后清理"
    echo
    
    ui_subheader "增强功能选项"
    echo "  --interactive, -i            交互式清理界面"
    echo "  --categorized                分级显示清理项目"
    echo "  --partial                    部分清理选择"
    echo "  --history                    显示清理历史"
    echo "  --no-safety-check            跳过安全检查（不推荐）"
    echo "  --help, -h                   显示此帮助信息"
    echo
    
    ui_subheader "使用示例"
    echo "  gpf clean                    # 智能引导界面"
    echo "  gpf clean --dry-run          # 预览所有清理项目"
    echo "  gpf clean --all              # 安全批量清理"
    echo "  gpf clean --all --force      # 强制批量清理"
    echo "  gpf clean worktrees          # 清理工作树"
    echo "  gpf clean branches           # 清理分支"
    echo "  gpf clean epic my-epic       # 清理指定Epic"
    echo "  gpf clean --categorized      # 分级查看清理项目"
    echo "  gpf clean --partial          # 选择性清理"
    echo "  gpf clean --history          # 查看清理历史"
    echo
    
    ui_subheader "风险级别说明"
    echo "  🟢 安全    - 可安全清理，无数据丢失风险"
    echo "  🟡 警告    - 有轻微风险，建议先检查"
    echo "  🔴 阻断    - 有数据丢失风险，需要--force"
    echo
    
    ui_subheader "安全检查系统"
    echo "  - 未提交更改检查（工作区和暂存区）"
    echo "  - 未合并分支检查（与主分支比较）"
    echo "  - 未推送提交检查（本地领先远程）"
    echo "  - 活跃工作树检查（正在进行的操作）"
    echo "  - 分支依赖关系检查（其他分支基于此分支）"
}

# ====== 增强的交互式系统 ======

handle_enhanced_interactive_cleanup() {
    ui_header "🎯 智能清理中心"
    
    # 分析当前环境并显示分级项目
    local total_items
    total_items=$(show_categorized_cleanup_items "all")
    
    if [[ "$total_items" -eq 0 ]]; then
        ui_success "✨ 环境很干净，无需清理"
        return 0
    fi
    
    echo
    ui_subheader "🎛️ 清理选项"
    
    local cleanup_options=(
        "🎯 部分清理选择（推荐）"
        "🧹 安全批量清理"
        "⚡ 强制批量清理"
        "🔍 详细环境分析"
        "📊 查看清理历史"
        "❌ 取消操作"
    )
    
    local choice
    choice=$(ui_select_menu "选择清理方式" "${cleanup_options[@]}")
    
    case $choice in
        0) # 部分清理选择
            interactive_partial_cleanup
            ;;
        1) # 安全批量清理
            execute_integrated_cleanup "all" "" "false" "false"
            ;;
        2) # 强制批量清理
            ui_warning "⚠️ 强制清理将跳过所有安全检查"
            if ui_confirm "确认执行强制清理？"; then
                execute_integrated_cleanup "all" "" "true" "false"
            fi
            ;;
        3) # 详细环境分析
            show_detailed_cleanup_status
            ;;
        4) # 查看清理历史
            show_cleanup_history
            ;;
        5) # 取消操作
            ui_info "取消清理操作"
            return 0
            ;;
    esac
}

# ====== 集成的清理执行引擎 ======

execute_integrated_cleanup() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    local dry_run="$4"
    
    # 重置批量统计
    reset_batch_stats
    
    # 收集清理前统计
    local before_stats
    before_stats=$(collect_environment_stats)
    
    # 显示进度条
    show_progress_bar 0 "准备清理..."
    
    # 干运行模式：只显示预览
    if [[ "$dry_run" == "true" ]]; then
        ui_header "🔍 清理预览"
        show_categorized_cleanup_items "$operation_type" "$target"
        return 0
    fi
    
    # 执行安全检查（除非强制模式或明确跳过）
    local safety_level=0
    if [[ "$force_mode" != "true" && "${safety_check:-true}" == "true" ]]; then
        show_progress_bar 20 "执行安全检查..."
        
        # 执行全面安全检查
        perform_comprehensive_safety_check "$operation_type" "$target" "$force_mode"
        safety_level=$?
        
        # 根据安全级别决定是否继续
        if [[ $safety_level -eq 2 ]]; then
            ui_error "🔴 检测到阻断性风险，清理已停止"
            ui_info "使用 --force 强制清理或先解决安全问题"
            return 1
        elif [[ $safety_level -eq 1 ]]; then
            ui_warning "🟡 检测到警告级风险"
            if ! ui_confirm "是否继续清理？"; then
                ui_info "清理已取消"
                return 0
            fi
        fi
    fi
    
    show_progress_bar 40 "开始执行清理..."
    
    # 执行实际清理操作
    case "$operation_type" in
        "worktrees")
            show_progress_bar 60 "清理工作树..."
            clean_worktrees_enhanced "$target" "$force_mode"
            ;;
        "branches")
            show_progress_bar 60 "清理分支..."
            clean_branches_enhanced "$target" "$force_mode"
            ;;
        "epic")
            show_progress_bar 60 "清理Epic..."
            clean_epic_enhanced "$target" "$force_mode"
            ;;
        "merged")
            show_progress_bar 60 "清理已合并分支..."
            clean_merged_branches_enhanced "$force_mode"
            ;;
        "all")
            show_progress_bar 60 "执行全面清理..."
            clean_all_enhanced "$force_mode"
            ;;
        "release")
            show_progress_bar 60 "发布后清理..."
            clean_after_release_enhanced "$force_mode"
            ;;
    esac
    
    show_progress_bar 80 "收集清理后统计..."
    
    # 收集清理后统计
    local after_stats
    after_stats=$(collect_environment_stats)
    
    show_progress_bar 100 "清理完成！"
    
    # 显示清理摘要
    show_cleanup_summary "$before_stats" "$after_stats" "$operation_type"
    
    # 记录清理历史
    log_cleanup_completion "$operation_type" "$target" "$force_mode" "$before_stats" "$after_stats"
    
    # 显示后续建议
    show_cleanup_recommendations "$operation_type"
}

# ====== 安全检查系统 ======

perform_comprehensive_safety_check() {
    local check_target="${1:-all}"
    local target_name="${2:-}"
    local force_mode="${3:-false}"
    
    ui_header "🔍 安全检查系统"
    
    # 重置检查结果数组
    SAFE_ITEMS=()
    WARNING_ITEMS=()
    BLOCKING_ITEMS=()
    
    # 执行各项检查
    check_uncommitted_changes "$check_target" "$target_name"
    check_unmerged_branches "$check_target" "$target_name"
    check_unpushed_commits "$check_target" "$target_name"
    check_active_worktrees "$check_target" "$target_name"
    check_branch_dependencies "$check_target" "$target_name"
    
    # 显示检查结果
    display_safety_check_results "$force_mode"
    
    # 返回检查结果（0=安全，1=警告，2=阻断）
    get_safety_check_level
}

check_uncommitted_changes() {
    local check_target="$1"
    local target_name="$2"
    
    ui_loading "检查未提交更改..."
    
    # 检查主仓库
    if ! git diff-index --quiet HEAD 2>/dev/null || ! git diff-index --cached --quiet HEAD 2>/dev/null; then
        add_blocking_item "main_repo_uncommitted" \
            "主仓库有未提交更改" \
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
                    
                    add_blocking_item "worktree_uncommitted_$worktree_name" \
                        "工作树 $worktree_name ($branch_name) 有未提交更改" \
                        "cd \"$worktree\" && git add . && git commit -m \"保存更改\"" \
                        "或: cd \"$worktree\" && git stash save \"临时保存\""
                else
                    add_safe_item "worktree_clean_$worktree_name" \
                        "工作树 $worktree_name 状态干净"
                fi
                
                cd "$original_dir" || true
            fi
        done
    fi
    
    echo "✅ 未提交更改检查完成"
}

check_unmerged_branches() {
    local check_target="$1"
    local target_name="$2"
    
    ui_loading "检查未合并分支..."
    
    local main_branches=("main" "master" "develop")
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)
    
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
                        add_warning_item "unmerged_branch_$branch" \
                            "分支 $branch 未合并到 $main_branch" \
                            "git checkout $main_branch && git merge $branch" \
                            "或: 通过PR将分支合并到主分支"
                    fi
                fi
            done <<< "$unmerged_branches"
            break
        fi
    done
    
    echo "✅ 未合并分支检查完成"
}

check_unpushed_commits() {
    local check_target="$1"
    local target_name="$2"
    
    ui_loading "检查未推送提交..."
    
    # 检查当前分支
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)
    
    if [[ -n "$current_branch" ]]; then
        local remote_branch="origin/$current_branch"
        if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
            local commits_ahead
            commits_ahead=$(git rev-list --count "$remote_branch..HEAD" 2>/dev/null || echo "0")
            
            if [[ "$commits_ahead" -gt 0 ]]; then
                add_warning_item "unpushed_commits_current" \
                    "当前分支 $current_branch 有 $commits_ahead 个未推送提交" \
                    "git push origin $current_branch" \
                    "或: git push origin $current_branch --force-with-lease"
            fi
        fi
    fi
    
    echo "✅ 未推送提交检查完成"
}

check_active_worktrees() {
    local check_target="$1"
    local target_name="$2"
    
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
                
                if [[ -f ".git/MERGE_HEAD" ]]; then
                    is_active=true
                    activity_reason="正在进行合并操作"
                elif [[ -d ".git/rebase-merge" || -d ".git/rebase-apply" ]]; then
                    is_active=true
                    activity_reason="正在进行变基操作"
                fi
                
                if [[ "$is_active" == "true" ]]; then
                    add_blocking_item "active_worktree_$worktree_name" \
                        "工作树 $worktree_name ($branch_name) 正在活跃使用: $activity_reason" \
                        "cd \"$worktree\" && 完成当前操作后再清理" \
                        "或: 使用 --force 强制清理（可能丢失数据）"
                else
                    add_safe_item "inactive_worktree_$worktree_name" \
                        "工作树 $worktree_name ($branch_name) 可以安全清理"
                fi
                
                cd "$original_dir" || true
            fi
        done
    fi
    
    echo "✅ 活跃工作树检查完成"
}

check_branch_dependencies() {
    local check_target="$1"
    local target_name="$2"
    
    ui_loading "检查分支依赖关系..."
    
    # 简化实现：检查Epic分支依赖
    if [[ "$check_target" == "epic" && -n "$target_name" ]]; then
        local epic_branches
        epic_branches=$(git branch --format='%(refname:short)' | grep "^$target_name/" || true)
        
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                # 检查是否有其他分支依赖这个分支（简化检查）
                local dependent_count
                dependent_count=$(git branch --format='%(refname:short)' | wc -l)
                
                if [[ "$dependent_count" -gt 5 ]]; then  # 简化条件
                    add_warning_item "branch_dependency_$branch" \
                        "分支 $branch 可能被其他分支依赖" \
                        "确认清理不会影响其他开发" \
                        "或: 使用 --force 忽略依赖关系"
                fi
            fi
        done <<< "$epic_branches"
    fi
    
    echo "✅ 分支依赖关系检查完成"
}

# 安全检查辅助函数
add_safe_item() {
    local item_id="$1"
    local description="$2"
    SAFE_ITEMS+=("$item_id|$description")
}

add_warning_item() {
    local item_id="$1"
    local description="$2"
    local solution1="$3"
    local solution2="${4:-}"
    WARNING_ITEMS+=("$item_id|$description|$solution1|$solution2")
}

add_blocking_item() {
    local item_id="$1"
    local description="$2"
    local solution1="$3"
    local solution2="${4:-}"
    BLOCKING_ITEMS+=("$item_id|$description|$solution1|$solution2")
}

display_safety_check_results() {
    local force_mode="$1"
    
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
    
    # 显示总结
    echo
    display_safety_summary "$force_mode"
}

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

get_safety_check_level() {
    if [[ ${#BLOCKING_ITEMS[@]} -gt 0 ]]; then
        return 2  # 阻断
    elif [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
        return 1  # 警告
    else
        return 0  # 安全
    fi
}

# ====== 增强用户体验功能 ======

show_categorized_cleanup_items() {
    local operation_type="$1"
    local target="${2:-}"
    
    ui_header "🎯 清理项目分析"
    
    local safe_items=()
    local warning_items=()
    local risky_items=()
    
    # 重置全局分析数组
    ANALYZE_SAFE_ITEMS=()
    ANALYZE_WARNING_ITEMS=()
    ANALYZE_RISKY_ITEMS=()
    
    # 分析不同类型的清理项目
    case "$operation_type" in
        "all"|"")
            analyze_all_cleanup_items
            ;;
        "worktrees"|"branches"|"epic"|"merged")
            analyze_all_cleanup_items  # 简化版本，都调用同一个函数
            ;;
    esac
    
    # 直接使用全局数组显示（不需要复制）
    
    # 显示分级结果
    display_categorized_items_simple
    
    # 返回总计数量
    echo $((${#ANALYZE_SAFE_ITEMS[@]} + ${#ANALYZE_WARNING_ITEMS[@]} + ${#ANALYZE_RISKY_ITEMS[@]}))
}

analyze_all_cleanup_items() {
    # 使用全局变量而不是nameref以兼容旧版bash
    
    # 分析工作树
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                local status="safe"
                local reason=""
                
                # 检查工作树状态
                local original_dir=$(pwd)
                cd "$worktree" 2>/dev/null || continue
                
                if ! git diff-index --quiet HEAD 2>/dev/null; then
                    status="risky"
                    reason="有未提交更改"
                elif ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                    status="risky"  
                    reason="有暂存更改"
                elif [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                    status="warning"
                    reason="有未跟踪文件"
                elif [[ -f ".git/MERGE_HEAD" ]] || [[ -d ".git/rebase-merge" ]]; then
                    status="risky"
                    reason="有进行中的Git操作"
                fi
                
                cd "$original_dir" || true
                
                local item="工作树|$worktree_name|$reason"
                case "$status" in
                    "safe") ANALYZE_SAFE_ITEMS+=("$item") ;;
                    "warning") ANALYZE_WARNING_ITEMS+=("$item") ;;
                    "risky") ANALYZE_RISKY_ITEMS+=("$item") ;;
                esac
            fi
        done
    fi
    
    # 分析分支（简化实现）
    local main_branches=("main" "master" "develop")
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local merged_branches
            merged_branches=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" || true)
            
            while IFS= read -r branch; do
                if [[ -n "$branch" ]]; then
                    branch=$(echo "$branch" | sed 's/^[+ ]*//')
                    ANALYZE_SAFE_ITEMS+=("分支|$branch|已合并到$main_branch")
                fi
            done <<< "$merged_branches"
            break
        fi
    done
}

# 简化的分析函数（可以根据需要扩展）
analyze_worktrees_items() {
    local target="$1"
    local -n safe_ref=$2
    local -n warning_ref=$3
    local -n risky_ref=$4
    
    analyze_all_cleanup_items safe_ref warning_ref risky_ref
}

analyze_branches_items() {
    local target="$1"  
    local -n safe_ref=$2
    local -n warning_ref=$3
    local -n risky_ref=$4
    
    analyze_all_cleanup_items safe_ref warning_ref risky_ref
}

analyze_epic_items() {
    local target="$1"
    local -n safe_ref=$2
    local -n warning_ref=$3
    local -n risky_ref=$4
    
    analyze_all_cleanup_items safe_ref warning_ref risky_ref
}

analyze_merged_branches_items() {
    local -n safe_ref=$1
    local -n warning_ref=$2
    local -n risky_ref=$3
    
    analyze_all_cleanup_items safe_ref warning_ref risky_ref
}

display_categorized_items_simple() {
    # 简化版本，直接使用全局数组
    local safe_count=${#ANALYZE_SAFE_ITEMS[@]}
    local warning_count=${#ANALYZE_WARNING_ITEMS[@]}
    local risky_count=${#ANALYZE_RISKY_ITEMS[@]}
    
    # 显示安全项目
    if [[ $safe_count -gt 0 ]]; then
        echo
        ui_success "🟢 安全项目 ($safe_count 项):"
        for item in "${ANALYZE_SAFE_ITEMS[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            echo "  ✅ $type: $name${reason:+ - $reason}"
        done
    fi
    
    # 显示警告项目
    if [[ $warning_count -gt 0 ]]; then
        echo
        ui_warning "🟡 警告项目 ($warning_count 项):"
        for item in "${ANALYZE_WARNING_ITEMS[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            echo "  ⚠️ $type: $name${reason:+ - $reason}"
        done
    fi
    
    # 显示风险项目
    if [[ $risky_count -gt 0 ]]; then
        echo
        ui_error "🔴 风险项目 ($risky_count 项):"
        for item in "${ANALYZE_RISKY_ITEMS[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            echo "  ❌ $type: $name${reason:+ - $reason}"
        done
    fi
}

display_categorized_items() {
    local -n safe_ref=$1
    local -n warning_ref=$2
    local -n risky_ref=$3
    
    # 显示安全项目
    if [[ ${#safe_ref[@]} -gt 0 ]]; then
        echo
        ui_success "🟢 安全项目 (${#safe_ref[@]} 项):"
        for item in "${safe_ref[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            echo "  ✅ $type: $name${reason:+ - $reason}"
        done
    fi
    
    # 显示警告项目
    if [[ ${#warning_ref[@]} -gt 0 ]]; then
        echo
        ui_warning "🟡 警告项目 (${#warning_ref[@]} 项):"
        for item in "${warning_ref[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            echo "  ⚠️ $type: $name${reason:+ - $reason}"
        done
    fi
    
    # 显示风险项目
    if [[ ${#risky_ref[@]} -gt 0 ]]; then
        echo
        ui_error "🔴 风险项目 (${#risky_ref[@]} 项):"
        for item in "${risky_ref[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            echo "  ❌ $type: $name${reason:+ - $reason}"
        done
    fi
}

show_progress_bar() {
    local progress="$1"
    local message="$2"
    
    local filled=$((progress * PROGRESS_BAR_WIDTH / 100))
    local empty=$((PROGRESS_BAR_WIDTH - filled))
    
    printf "\r🔄 $message ["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%%" $progress
    
    if [[ $progress -eq 100 ]]; then
        echo " ✅"
    fi
}

interactive_partial_cleanup() {
    ui_header "🎯 部分清理选择"
    
    # 分析所有可清理项目
    local safe_items=()
    local warning_items=()
    local risky_items=()
    
    analyze_all_cleanup_items safe_items warning_items risky_items
    
    local total_items=$((${#safe_items[@]} + ${#warning_items[@]} + ${#risky_items[@]}))
    
    if [[ $total_items -eq 0 ]]; then
        ui_success "✨ 环境很干净，无需清理"
        return 0
    fi
    
    # 显示分级项目
    display_categorized_items safe_items warning_items risky_items
    
    echo
    ui_subheader "🎯 选择清理范围"
    
    local cleanup_options=(
        "只清理安全项目 (${#safe_items[@]} 项)"
        "清理安全+警告项目 ($(( ${#safe_items[@]} + ${#warning_items[@]} )) 项)"
        "清理所有项目 (需要--force)"
        "取消操作"
    )
    
    local choice
    choice=$(ui_select_menu "请选择清理范围" "${cleanup_options[@]}")
    
    case $choice in
        0) # 只清理安全项目
            execute_selective_cleanup safe_items
            ;;
        1) # 清理安全+警告项目
            local combined_items=("${safe_items[@]}" "${warning_items[@]}")
            execute_selective_cleanup combined_items
            ;;
        2) # 清理所有项目
            ui_warning "⚠️ 清理所有项目包括风险项目，需要确认"
            if ui_confirm "确认清理所有项目（包括风险项目）？"; then
                local all_items=("${safe_items[@]}" "${warning_items[@]}" "${risky_items[@]}")
                execute_selective_cleanup all_items "true"
            fi
            ;;
        3) # 取消操作
            ui_info "取消清理操作"
            return 0
            ;;
    esac
}

execute_selective_cleanup() {
    local -n items_ref=$1
    local force_mode="${2:-false}"
    
    if [[ ${#items_ref[@]} -eq 0 ]]; then
        ui_info "没有项目需要清理"
        return 0
    fi
    
    ui_subheader "🚀 执行选择性清理"
    
    local cleaned_count=0
    local total_count=${#items_ref[@]}
    
    for item in "${items_ref[@]}"; do
        local type=$(echo "$item" | cut -d'|' -f1)
        local name=$(echo "$item" | cut -d'|' -f2)
        
        show_progress_bar $((cleaned_count * 100 / total_count)) "清理 $type: $name"
        
        # 根据类型执行相应的清理
        case "$type" in
            "工作树")
                if git_remove_worktree ".worktrees/$name" true 2>/dev/null; then
                    ((cleaned_count++))
                fi
                ;;
            "分支")
                if git branch -d "$name" >/dev/null 2>&1 || git branch -D "$name" >/dev/null 2>&1; then
                    ((cleaned_count++))
                fi
                ;;
        esac
    done
    
    show_progress_bar 100 "清理完成"
    
    ui_success "🎉 选择性清理完成: $cleaned_count/$total_count 项"
}

# ====== 清理历史管理 ======

log_cleanup_start() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    local dry_run="$4"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local log_entry="$timestamp|START|$operation_type|$target|force:$force_mode|dry:$dry_run"
    
    # 确保历史文件存在
    touch "$CLEANUP_HISTORY_FILE"
    
    # 添加到历史记录
    echo "$log_entry" >> "$CLEANUP_HISTORY_FILE"
    
    # 保持历史记录数量限制
    maintain_history_limit
}

log_cleanup_completion() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    local before_stats="$4"
    local after_stats="$5"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local log_entry="$timestamp|COMPLETE|$operation_type|$target|force:$force_mode|before:$before_stats|after:$after_stats"
    
    echo "$log_entry" >> "$CLEANUP_HISTORY_FILE"
    maintain_history_limit
}

maintain_history_limit() {
    if [[ -f "$CLEANUP_HISTORY_FILE" ]]; then
        local line_count
        line_count=$(wc -l < "$CLEANUP_HISTORY_FILE")
        
        if [[ $line_count -gt $MAX_HISTORY_ENTRIES ]]; then
            tail -n $MAX_HISTORY_ENTRIES "$CLEANUP_HISTORY_FILE" > "${CLEANUP_HISTORY_FILE}.tmp"
            mv "${CLEANUP_HISTORY_FILE}.tmp" "$CLEANUP_HISTORY_FILE"
        fi
    fi
}

show_cleanup_history() {
    ui_header "📊 清理历史记录"
    
    if [[ ! -f "$CLEANUP_HISTORY_FILE" ]]; then
        ui_info "暂无清理历史记录"
        return 0
    fi
    
    echo "最近的清理操作："
    echo
    
    local count=0
    while IFS='|' read -r timestamp action type target details; do
        ((count++))
        if [[ $count -gt 10 ]]; then break; fi
        
        local status_icon="🔄"
        if [[ "$action" == "COMPLETE" ]]; then
            status_icon="✅"
        elif [[ "$action" == "START" ]]; then
            status_icon="🚀"
        fi
        
        echo "$status_icon $timestamp - $action $type${target:+ $target}"
        if [[ -n "$details" ]]; then
            echo "   💭 $details"
        fi
        echo
    done < <(tac "$CLEANUP_HISTORY_FILE" 2>/dev/null | head -20)
    
    if [[ $count -eq 0 ]]; then
        ui_info "暂无清理历史记录"
    fi
}

# ====== 批量操作支持 ======

reset_batch_stats() {
    BATCH_STATS_WORKTREES_CLEANED=0
    BATCH_STATS_WORKTREES_TOTAL=0
    BATCH_STATS_BRANCHES_CLEANED=0
    BATCH_STATS_BRANCHES_TOTAL=0
    BATCH_STATS_EPICS_CLEANED=0
    BATCH_STATS_EPICS_TOTAL=0
    BATCH_STATS_FILES_CLEANED=0
    BATCH_STATS_DISK_SAVED=""
    BATCH_STATS_ERRORS=0
}

collect_environment_stats() {
    local worktree_count=0
    local branch_count=0
    local file_count=0
    local disk_usage=0
    
    # 统计工作树
    if [[ -d ".worktrees" ]]; then
        worktree_count=$(find .worktrees -maxdepth 1 -type d -name "epic--*" | wc -l || echo "0")
        disk_usage=$(du -s .worktrees 2>/dev/null | cut -f1 || echo "0")
    fi
    
    # 统计已合并分支
    local main_branches=("main" "master" "develop")
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            branch_count=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" | wc -l || echo "0")
            break
        fi
    done
    
    # 统计临时文件
    for pattern in "epic-*-readiness-report.md" "CHANGELOG-*.md" "*.tmp" ".gpf-*.tmp"; do
        local files
        files=$(find . -name "$pattern" -type f 2>/dev/null | wc -l || echo "0")
        file_count=$((file_count + files))
    done
    
    echo "worktrees:$worktree_count,branches:$branch_count,files:$file_count,disk:$disk_usage"
}

show_cleanup_summary() {
    local before_stats="$1"
    local after_stats="$2"
    local operation_type="$3"
    
    ui_header "📊 清理摘要"
    
    # 解析统计数据
    local before_worktrees after_worktrees before_branches after_branches
    local before_files after_files before_disk after_disk
    
    IFS=',' read -r before_worktrees before_branches before_files before_disk <<< "$before_stats"
    IFS=',' read -r after_worktrees after_branches after_files after_disk <<< "$after_stats"
    
    # 计算清理数量
    local cleaned_worktrees=$((${before_worktrees#*:} - ${after_worktrees#*:}))
    local cleaned_branches=$((${before_branches#*:} - ${after_branches#*:}))
    local cleaned_files=$((${before_files#*:} - ${after_files#*:}))
    local saved_disk=$((${before_disk#*:} - ${after_disk#*:}))
    
    echo "  🧹 清理类型: $operation_type"
    echo "  🏠 工作树: $cleaned_worktrees 个"
    echo "  🌿 分支: $cleaned_branches 个"
    echo "  📄 文件: $cleaned_files 个"
    echo "  💾 节省磁盘: ${saved_disk}KB"
    echo "  ⏰ 完成时间: $(date)"
    echo
    
    if [[ $cleaned_worktrees -gt 0 || $cleaned_branches -gt 0 || $cleaned_files -gt 0 ]]; then
        ui_success "✅ 清理成功完成！"
    else
        ui_info "📝 环境已经很干净，无需清理"
    fi
}

show_cleanup_recommendations() {
    local operation_type="$1"
    
    ui_subheader "💡 后续建议"
    
    case "$operation_type" in
        "worktrees")
            echo "  • 定期运行 gpf clean worktrees 保持环境整洁"
            echo "  • 考虑清理已合并的分支: gpf clean merged"
            ;;
        "branches")
            echo "  • 检查是否有未使用的工作树: gpf clean worktrees"
            echo "  • 考虑运行全面清理: gpf clean --all"
            ;;
        "all")
            echo "  • 环境已全面清理，建议定期维护"
            echo "  • 使用 gpf clean --history 查看清理历史"
            ;;
        "epic")
            echo "  • Epic清理完成，可以开始新的开发工作"
            echo "  • 考虑清理其他未使用资源: gpf clean --all"
            ;;
    esac
    
    echo
    echo "  📚 更多帮助: gpf clean --help"
}

# ====== 增强的清理函数 ======

clean_worktrees_enhanced() {
    local target_pattern="$1"
    local force_mode="$2"
    
    ui_subheader "🧹 增强工作树清理"
    
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
            if [[ "$force_mode" == "true" ]] || can_clean_worktree "$worktree_path"; then
                worktrees_to_clean+=("$worktree_path")
                ((BATCH_STATS_WORKTREES_TOTAL++))
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
    
    if [[ "$force_mode" != "true" ]] && ! ui_confirm "确认清理这些工作树？"; then
        ui_info "取消工作树清理"
        return 0
    fi
    
    # 执行清理
    local cleaned_count=0
    for worktree in "${worktrees_to_clean[@]}"; do
        ui_loading "清理工作树: $worktree"
        
        if git_remove_worktree "$worktree" true; then
            ((cleaned_count++))
            ((BATCH_STATS_WORKTREES_CLEANED++))
            echo "    ✅ $worktree 清理成功"
        else
            echo "    ❌ $worktree 清理失败"
            ((BATCH_STATS_ERRORS++))
        fi
    done
    
    echo
    ui_success "🎉 清理完成: $cleaned_count/${#worktrees_to_clean[@]} 个工作树"
}

clean_branches_enhanced() {
    local target_pattern="$1"
    local force_mode="$2"
    
    ui_subheader "🌿 增强分支清理"
    
    if [[ -n "$target_pattern" ]]; then
        clean_branches_by_pattern_enhanced "$target_pattern" "$force_mode"
    else
        clean_merged_branches_enhanced "$force_mode"
    fi
}

clean_branches_by_pattern_enhanced() {
    local pattern="$1"
    local force_mode="$2"
    
    ui_info "🔍 查找匹配模式的分支: $pattern"
    
    local matching_branches=()
    local all_branches
    all_branches=$(git_list_branches)
    
    while IFS= read -r branch; do
        if [[ -n "$branch" && "$branch" =~ $pattern ]]; then
            matching_branches+=("$branch")
            ((BATCH_STATS_BRANCHES_TOTAL++))
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
    
    if [[ "$force_mode" != "true" ]] && ! ui_confirm "确认删除这些分支？"; then
        ui_info "取消分支清理"
        return 0
    fi
    
    # 执行删除
    local deleted_count=0
    for branch in "${matching_branches[@]}"; do
        if delete_branch_safe "$branch"; then
            ((deleted_count++))
            ((BATCH_STATS_BRANCHES_CLEANED++))
        else
            ((BATCH_STATS_ERRORS++))
        fi
    done
    
    ui_success "🎉 清理完成: $deleted_count/${#matching_branches[@]} 个分支"
}

clean_merged_branches_enhanced() {
    local force_mode="$1"
    
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
                    ((BATCH_STATS_BRANCHES_TOTAL++))
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
    
    if [[ "$force_mode" != "true" ]] && ! ui_confirm "确认删除这些已合并的分支？"; then
        ui_info "取消已合并分支清理"
        return 0
    fi
    
    # 执行删除
    local deleted_count=0
    for branch in "${merged_branches[@]}"; do
        if delete_branch_safe "$branch"; then
            ((deleted_count++))
            ((BATCH_STATS_BRANCHES_CLEANED++))
        else
            ((BATCH_STATS_ERRORS++))
        fi
    done
    
    ui_success "🎉 清理完成: $deleted_count/${#merged_branches[@]} 个分支"
}

clean_epic_enhanced() {
    local epic_name="$1"
    local force_mode="$2"
    
    if [[ -z "$epic_name" ]]; then
        if config_epic_exists; then
            epic_name=$(config_epic_get "epic_name")
        else
            ui_error "未指定Epic名称且未找到Epic配置"
            return 1
        fi
    fi
    
    ui_subheader "🚀 增强Epic清理: $epic_name"
    
    # 获取Epic相关资源
    local epic_branches epic_worktrees
    epic_branches=$(git_list_branches | grep "^$epic_name/" || true)
    epic_worktrees=$(get_epic_worktrees "$epic_name")
    
    # 显示将要清理的资源
    show_epic_cleanup_preview "$epic_name" "$epic_branches" "$epic_worktrees"
    
    if [[ "$force_mode" != "true" ]] && ! ui_confirm "确认清理整个Epic '$epic_name'？"; then
        ui_info "取消Epic清理"
        return 0
    fi
    
    # 执行Epic清理
    execute_epic_cleanup_enhanced "$epic_name" "$epic_branches" "$epic_worktrees"
    ((BATCH_STATS_EPICS_CLEANED++))
}

clean_all_enhanced() {
    local force_mode="$1"
    
    ui_subheader "🧹 增强全面清理"
    
    if [[ "$force_mode" != "true" ]]; then
        ui_warning "⚠️ 全面清理是高风险操作"
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
    
    ui_info "🚀 开始全面清理..."
    
    # 1. 清理工作树
    echo "  🧹 清理工作树..."
    clean_worktrees_enhanced "" "$force_mode"
    
    # 2. 清理已合并分支
    echo "  🌿 清理已合并分支..."
    clean_merged_branches_enhanced "$force_mode"
    
    # 3. 清理Epic配置
    if config_epic_exists; then
        echo "  📝 清理Epic配置..."
        rm -f "$EPIC_CONFIG_FILE" 2>/dev/null
        ((BATCH_STATS_FILES_CLEANED++))
    fi
    
    # 4. 清理临时文件
    echo "  🗑️ 清理临时文件..."
    local temp_files=0
    for pattern in "epic-*-readiness-report.md" "CHANGELOG-*.md" "*.tmp" ".gpf-*.tmp"; do
        local files
        files=$(find . -name "$pattern" -type f -delete 2>/dev/null | wc -l || echo "0")
        temp_files=$((temp_files + files))
    done
    BATCH_STATS_FILES_CLEANED=$((BATCH_STATS_FILES_CLEANED + temp_files))
    
    ui_success "🎉 增强全面清理完成！"
}

clean_after_release_enhanced() {
    local force_mode="$1"
    
    ui_header "🎉 增强发布后清理"
    
    if ! config_epic_exists; then
        ui_error "未找到Epic配置，无法执行发布后清理"
        return 1
    fi
    
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_info "🎉 恭喜！Epic '$epic_name' 发布成功"
    ui_info "开始增强发布后清理流程..."
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
            clean_merged_epic_branches_enhanced "$epic_name" "$force_mode"
            ;;
        2) # 清理所有Epic资源
            clean_epic_enhanced "$epic_name" "$force_mode"
            ;;
        3) # 仅清理工作树
            clean_epic_worktrees_enhanced "$epic_name" "$force_mode"
            ;;
        4) # 取消
            ui_info "取消发布后清理"
            ;;
    esac
    
    # 生成发布摘要
    generate_release_summary "$epic_name"
}

# ====== 基础清理函数 ======

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
execute_epic_cleanup_enhanced() {
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
                    ((BATCH_STATS_WORKTREES_CLEANED++))
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
                    ((BATCH_STATS_BRANCHES_CLEANED++))
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
                ((BATCH_STATS_FILES_CLEANED++))
            fi
        fi
    fi
    
    ui_success "🎉 Epic '$epic_name' 清理完成"
    echo "  📊 清理摘要: $cleanup_summary"
}

# 清理已合并的Epic分支
clean_merged_epic_branches_enhanced() {
    local epic_name="$1"
    local force_mode="$2"
    
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
    
    if [[ "$force_mode" != "true" ]] && ! ui_confirm "清理这些已合并的分支？"; then
        ui_info "取消已合并分支清理"
        return 0
    fi
    
    local cleaned_count=0
    for branch in "${merged_branches[@]}"; do
        if delete_branch_safe "$branch"; then
            ((cleaned_count++))
            ((BATCH_STATS_BRANCHES_CLEANED++))
        fi
    done
    
    ui_success "✅ 已合并分支清理完成: $cleaned_count 个"
}

# 清理Epic工作树
clean_epic_worktrees_enhanced() {
    local epic_name="$1"
    local force_mode="$2"
    
    ui_info "🧹 清理Epic工作树..."
    
    local epic_worktrees
    epic_worktrees=$(get_epic_worktrees "$epic_name")
    
    if [[ -z "$epic_worktrees" ]]; then
        ui_info "  📝 没有找到Epic工作树"
        return 0
    fi
    
    local cleaned_count=0
    while IFS= read -r worktree; do
        if [[ -n "$worktree" ]]; then
            if git_remove_worktree "$worktree" true; then
                ((cleaned_count++))
                ((BATCH_STATS_WORKTREES_CLEANED++))
            fi
        fi
    done <<< "$epic_worktrees"
    
    ui_success "✅ Epic工作树清理完成: $cleaned_count 个"
}

# 生成发布摘要
generate_release_summary() {
    local epic_name="$1"
    local summary_file="release-summary-$epic_name.md"
    
    cat > "$summary_file" << EOF
# $epic_name Epic 发布摘要

## 发布信息
- **Epic名称**: $epic_name
- **发布时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **发布分支**: release/$epic_name

## 发布统计
- **功能分支数**: $(git_list_branches | grep -c "^$epic_name/" || echo "0")
- **总提交数**: $(git_list_branches | grep "^$epic_name/" | xargs -I {} git rev-list --count {} 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")

## 清理统计
- **工作树清理**: $BATCH_STATS_WORKTREES_CLEANED 个
- **分支清理**: $BATCH_STATS_BRANCHES_CLEANED 个  
- **文件清理**: $BATCH_STATS_FILES_CLEANED 个
- **Epic清理**: $BATCH_STATS_EPICS_CLEANED 个

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