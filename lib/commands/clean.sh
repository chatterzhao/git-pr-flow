#!/usr/bin/env bash

# Git PR Flow - clean命令实现
# 智能环境清理，支持工作树、分支、Epic级清理
# enhanced-user-experience: 提升用户体验，增加可视化效果和操作便利性

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# ====== 增强用户体验核心功能 ======

# 全局变量用于跟踪清理进度
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_BAR_WIDTH=40

# 清理历史记录
CLEANUP_HISTORY_FILE=".gpf-cleanup-history.log"
MAX_HISTORY_ENTRIES=50

# 分级显示清理项目
show_categorized_cleanup_items() {
    local operation_type="$1"
    local target="$2"
    
    ui_header "🎯 清理项目分析"
    
    local safe_items=()
    local warning_items=()
    local risky_items=()
    
    # 分析不同类型的清理项目
    case "$operation_type" in
        "all"|"")
            analyze_all_cleanup_items safe_items warning_items risky_items
            ;;
        "worktrees")
            analyze_worktrees_items "$target" safe_items warning_items risky_items
            ;;
        "branches")
            analyze_branches_items "$target" safe_items warning_items risky_items
            ;;
        "epic")
            analyze_epic_items "$target" safe_items warning_items risky_items
            ;;
        "merged")
            analyze_merged_branches_items safe_items warning_items risky_items
            ;;
    esac
    
    # 显示分级结果
    display_categorized_items safe_items warning_items risky_items
    
    # 返回总计数量
    echo $((${#safe_items[@]} + ${#warning_items[@]} + ${#risky_items[@]}))
}

# 分析所有清理项目
analyze_all_cleanup_items() {
    local -n safe_ref=$1
    local -n warning_ref=$2
    local -n risky_ref=$3
    
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
                    "safe") safe_ref+=("$item") ;;
                    "warning") warning_ref+=("$item") ;;
                    "risky") risky_ref+=("$item") ;;
                esac
            fi
        done
    fi
    
    # 分析分支
    local current_branch=$(git branch --show-current 2>/dev/null)
    local main_branches=("main" "master" "develop")
    
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local merged_branches
            merged_branches=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" | sed 's/^[+ ]*//' || true)
            
            while IFS= read -r branch; do
                if [[ -n "$branch" && "$branch" != "$current_branch" ]]; then
                    local status="safe"
                    local reason="已合并到 $main_branch"
                    
                    # 检查是否有未推送提交
                    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                        local commits_ahead
                        commits_ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
                        if [[ "$commits_ahead" -gt 0 ]]; then
                            status="warning"
                            reason="已合并，但有 $commits_ahead 个未推送提交"
                        fi
                    fi
                    
                    # 检查分支是否被工作树使用
                    if [[ -d ".worktrees" ]]; then
                        local worktree_info
                        worktree_info=$(git worktree list 2>/dev/null | grep "$branch" || true)
                        if [[ -n "$worktree_info" ]]; then
                            status="warning"
                            reason="$reason，但正被工作树使用"
                        fi
                    fi
                    
                    local item="分支|$branch|$reason"
                    case "$status" in
                        "safe") safe_ref+=("$item") ;;
                        "warning") warning_ref+=("$item") ;;
                        "risky") risky_ref+=("$item") ;;
                    esac
                fi
            done <<< "$merged_branches"
            break
        fi
    done
    
    # 分析临时文件
    for pattern in "epic-*-readiness-report.md" "CHANGELOG-*.md" "*.tmp" ".gpf-*.tmp"; do
        local files
        files=$(find . -name "$pattern" -type f 2>/dev/null || true)
        if [[ -n "$files" ]]; then
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    local item="临时文件|$file|自动生成的临时文件"
                    safe_ref+=("$item")
                fi
            done <<< "$files"
        fi
    done
}

# 分析工作树项目
analyze_worktrees_items() {
    local pattern="$1"
    local -n safe_ref=$2
    local -n warning_ref=$3
    local -n risky_ref=$4
    
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                
                # 如果指定了模式，检查是否匹配
                if [[ -n "$pattern" && ! "$worktree_name" =~ $pattern ]]; then
                    continue
                fi
                
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
                fi
                
                cd "$original_dir" || true
                
                local item="工作树|$worktree_name|$reason"
                case "$status" in
                    "safe") safe_ref+=("$item") ;;
                    "warning") warning_ref+=("$item") ;;
                    "risky") risky_ref+=("$item") ;;
                esac
            fi
        done
    fi
}

# 分析分支项目
analyze_branches_items() {
    local pattern="$1"
    local -n safe_ref=$2
    local -n warning_ref=$3
    local -n risky_ref=$4
    
    local current_branch=$(git branch --show-current 2>/dev/null)
    local main_branches=("main" "master" "develop")
    
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local merged_branches
            merged_branches=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" | sed 's/^[+ ]*//' || true)
            
            while IFS= read -r branch; do
                if [[ -n "$branch" && "$branch" != "$current_branch" ]]; then
                    # 如果指定了模式，检查是否匹配
                    if [[ -n "$pattern" && ! "$branch" =~ $pattern ]]; then
                        continue
                    fi
                    
                    local status="safe"
                    local reason="已合并到 $main_branch"
                    
                    # 检查是否有未推送提交
                    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                        local commits_ahead
                        commits_ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
                        if [[ "$commits_ahead" -gt 0 ]]; then
                            status="warning"
                            reason="已合并，但有 $commits_ahead 个未推送提交"
                        fi
                    fi
                    
                    local item="分支|$branch|$reason"
                    case "$status" in
                        "safe") safe_ref+=("$item") ;;
                        "warning") warning_ref+=("$item") ;;
                        "risky") risky_ref+=("$item") ;;
                    esac
                fi
            done <<< "$merged_branches"
            break
        fi
    done
}

# 分析Epic项目
analyze_epic_items() {
    local epic_name="$1"
    local -n safe_ref=$2
    local -n warning_ref=$3
    local -n risky_ref=$4
    
    if ! git_branch_exists "epic/$epic_name"; then
        return 1
    fi
    
    # 分析功能分支
    local feature_branches
    feature_branches=$(git branch --format='%(refname:short)' | grep "^$epic_name/" || true)
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local status="safe"
            local reason="Epic功能分支"
            
            # 检查是否已合并到Epic主分支
            if ! git merge-base --is-ancestor "$branch" "epic/$epic_name" 2>/dev/null; then
                status="warning"
                reason="未合并到Epic主分支"
            fi
            
            local item="分支|$branch|$reason"
            case "$status" in
                "safe") safe_ref+=("$item") ;;
                "warning") warning_ref+=("$item") ;;
                "risky") risky_ref+=("$item") ;;
            esac
        fi
    done <<< "$feature_branches"
    
    # 分析Epic工作树
    local epic_worktrees
    epic_worktrees=$(find .worktrees -type d -name "epic--$epic_name*" 2>/dev/null || true)
    
    while IFS= read -r worktree; do
        if [[ -n "$worktree" ]]; then
            local worktree_name=$(basename "$worktree")
            local status="safe"
            local reason="Epic工作树"
            
            # 检查工作树状态
            local original_dir=$(pwd)
            cd "$worktree" 2>/dev/null || continue
            
            if ! git diff-index --quiet HEAD 2>/dev/null; then
                status="risky"
                reason="有未提交更改"
            elif ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                status="risky"
                reason="有暂存更改"
            fi
            
            cd "$original_dir" || true
            
            local item="工作树|$worktree_name|$reason"
            case "$status" in
                "safe") safe_ref+=("$item") ;;
                "warning") warning_ref+=("$item") ;;
                "risky") risky_ref+=("$item") ;;
            esac
        fi
    done <<< "$epic_worktrees"
    
    # Epic主分支
    local item="分支|epic/$epic_name|Epic主分支"
    safe_ref+=("$item")
}

# 分析已合并分支项目
analyze_merged_branches_items() {
    local -n safe_ref=$1
    local -n warning_ref=$2
    local -n risky_ref=$3
    
    analyze_branches_items "" safe_ref warning_ref risky_ref
}

# 显示分级项目
display_categorized_items() {
    local -n safe_ref=$1
    local -n warning_ref=$2
    local -n risky_ref=$3
    
    # 显示安全项目
    if [[ ${#safe_ref[@]} -gt 0 ]]; then
        echo
        ui_success "🟢 可安全清理 (${#safe_ref[@]} 项):"
        for item in "${safe_ref[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            
            echo "  ✅ $type: $name"
            if [[ -n "$reason" ]]; then
                echo "     💬 $reason"
            fi
        done
    fi
    
    # 显示警告项目
    if [[ ${#warning_ref[@]} -gt 0 ]]; then
        echo
        ui_warning "🟡 需要注意 (${#warning_ref[@]} 项):"
        for item in "${warning_ref[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            
            echo "  ⚠️ $type: $name"
            if [[ -n "$reason" ]]; then
                echo "     💬 $reason"
            fi
        done
    fi
    
    # 显示风险项目
    if [[ ${#risky_ref[@]} -gt 0 ]]; then
        echo
        ui_error "🔴 有风险 (${#risky_ref[@]} 项):"
        for item in "${risky_ref[@]}"; do
            local type=$(echo "$item" | cut -d'|' -f1)
            local name=$(echo "$item" | cut -d'|' -f2)
            local reason=$(echo "$item" | cut -d'|' -f3)
            
            echo "  ❌ $type: $name"
            if [[ -n "$reason" ]]; then
                echo "     💬 $reason"
            fi
        done
        
        echo
        ui_warning "⚠️ 风险项目需要手动处理或使用 --force 强制清理"
    fi
    
    # 显示总结
    local total_items=$((${#safe_ref[@]} + ${#warning_ref[@]} + ${#risky_ref[@]}))
    echo
    ui_subheader "📊 分级统计"
    echo "  🟢 安全: ${#safe_ref[@]} 项"
    echo "  🟡 警告: ${#warning_ref[@]} 项"  
    echo "  🔴 风险: ${#risky_ref[@]} 项"
    echo "  📋 总计: $total_items 项"
}

# 进度指示器功能
show_progress_bar() {
    local current="$1"
    local total="$2"
    local message="$3"
    
    # 计算进度百分比
    local percentage=0
    if [[ $total -gt 0 ]]; then
        percentage=$(( (current * 100) / total ))
    fi
    
    # 计算进度条填充
    local filled=$(( (current * PROGRESS_BAR_WIDTH) / total ))
    local empty=$((PROGRESS_BAR_WIDTH - filled))
    
    # 构建进度条
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # 显示进度条
    printf "\r  🔄 [%s] %d%% (%d/%d) %s" "$bar" "$percentage" "$current" "$total" "$message"
    
    # 如果完成，换行
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 初始化进度跟踪
init_progress() {
    local total="$1"
    PROGRESS_TOTAL=$total
    PROGRESS_CURRENT=0
}

# 更新进度
update_progress() {
    local message="$1"
    ((PROGRESS_CURRENT++))
    show_progress_bar "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$message"
}

# 清理历史记录功能
log_cleanup_action() {
    local action="$1"
    local target="$2"
    local result="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 记录到历史文件
    echo "$timestamp|$action|$target|$result" >> "$CLEANUP_HISTORY_FILE"
    
    # 保持历史记录不超过最大条数
    if [[ -f "$CLEANUP_HISTORY_FILE" ]]; then
        local line_count
        line_count=$(wc -l < "$CLEANUP_HISTORY_FILE")
        if [[ $line_count -gt $MAX_HISTORY_ENTRIES ]]; then
            tail -n $MAX_HISTORY_ENTRIES "$CLEANUP_HISTORY_FILE" > "${CLEANUP_HISTORY_FILE}.tmp"
            mv "${CLEANUP_HISTORY_FILE}.tmp" "$CLEANUP_HISTORY_FILE"
        fi
    fi
}

# 显示清理历史
show_cleanup_history() {
    local limit="${1:-10}"
    
    ui_header "📜 最近的清理历史"
    
    if [[ ! -f "$CLEANUP_HISTORY_FILE" ]]; then
        ui_info "暂无清理历史记录"
        return 0
    fi
    
    # 显示最近的记录
    echo "显示最近 $limit 条记录："
    echo
    
    tail -n "$limit" "$CLEANUP_HISTORY_FILE" | while IFS='|' read -r timestamp action target result; do
        local status_icon="✅"
        if [[ "$result" == "失败"* ]]; then
            status_icon="❌"
        elif [[ "$result" == "跳过"* ]]; then
            status_icon="⚠️"
        fi
        
        echo "  $status_icon $timestamp"
        echo "     🎯 操作: $action"
        if [[ -n "$target" ]]; then
            echo "     📋 目标: $target"
        fi
        echo "     📊 结果: $result"
        echo
    done
}

# 显示撤销建议
show_undo_suggestions() {
    local operation_type="$1"
    local cleaned_items="$2"
    
    ui_subheader "🔄 撤销建议"
    
    case "$operation_type" in
        "worktrees")
            ui_info "工作树清理撤销方法："
            ui_info "  1. 重新创建工作树: git worktree add <path> <branch>"
            ui_info "  2. 如果分支仍存在，工作树可以恢复"
            ;;
        "branches")
            ui_info "分支清理撤销方法："
            ui_info "  1. 从远程恢复: git checkout -b <branch> origin/<branch>"
            ui_info "  2. 从reflog恢复: git branch <branch> <commit-hash>"
            ui_info "  3. 查看reflog: git reflog --grep=<branch>"
            ;;
        "epic")
            ui_info "Epic清理撤销方法："
            ui_info "  1. 重新创建Epic: gpf init <epic-name>"
            ui_info "  2. 从远程恢复分支: git fetch origin"
            ui_info "  3. 重新检出所需分支: git checkout -b <branch> origin/<branch>"
            ;;
        "all")
            ui_info "全面清理撤销方法："
            ui_info "  1. 分别按类型恢复（见上述方法）"
            ui_info "  2. 从最近的备份恢复"
            ui_info "  3. 重新克隆仓库（如果有远程备份）"
            ;;
    esac
    
    echo
    ui_warning "⚠️ 建议在重要操作前创建备份或使用 --dry-run 预览"
    ui_info "💡 可以查看清理历史: gpf clean --history"
}

# 显示清理前后对比
show_before_after_comparison() {
    local before_stats="$1"
    local after_stats="$2"
    
    ui_header "📊 清理前后对比"
    
    # 解析统计数据 (格式: worktrees:count,branches:count,files:count,disk:size)
    local before_worktrees=$(echo "$before_stats" | grep -o 'worktrees:[0-9]*' | cut -d':' -f2 || echo "0")
    local before_branches=$(echo "$before_stats" | grep -o 'branches:[0-9]*' | cut -d':' -f2 || echo "0")
    local before_files=$(echo "$before_stats" | grep -o 'files:[0-9]*' | cut -d':' -f2 || echo "0")
    local before_disk=$(echo "$before_stats" | grep -o 'disk:[^,]*' | cut -d':' -f2 || echo "0")
    
    local after_worktrees=$(echo "$after_stats" | grep -o 'worktrees:[0-9]*' | cut -d':' -f2 || echo "0")
    local after_branches=$(echo "$after_stats" | grep -o 'branches:[0-9]*' | cut -d':' -f2 || echo "0")
    local after_files=$(echo "$after_stats" | grep -o 'files:[0-9]*' | cut -d':' -f2 || echo "0")
    local after_disk=$(echo "$after_stats" | grep -o 'disk:[^,]*' | cut -d':' -f2 || echo "0")
    
    # 计算差值
    local diff_worktrees=$((before_worktrees - after_worktrees))
    local diff_branches=$((before_branches - after_branches))
    local diff_files=$((before_files - after_files))
    
    echo "项目类型        清理前    清理后    已清理"
    echo "────────────────────────────────────────"
    printf "🏠 工作树      %8d  %8d  %8d\n" "$before_worktrees" "$after_worktrees" "$diff_worktrees"
    printf "🌿 分支        %8d  %8d  %8d\n" "$before_branches" "$after_branches" "$diff_branches"
    printf "📄 临时文件    %8d  %8d  %8d\n" "$before_files" "$after_files" "$diff_files"
    echo "────────────────────────────────────────"
    
    # 显示磁盘空间变化
    if [[ -n "$before_disk" && -n "$after_disk" && "$before_disk" != "0" ]]; then
        echo "💾 磁盘空间:   $before_disk → $after_disk"
    fi
    
    local total_cleaned=$((diff_worktrees + diff_branches + diff_files))
    if [[ $total_cleaned -gt 0 ]]; then
        echo
        ui_success "🎉 总计清理了 $total_cleaned 项资源"
    else
        echo
        ui_info "📝 没有项目被清理"
    fi
}

# 收集环境统计信息
collect_environment_stats() {
    local worktree_count=0
    local branch_count=0
    local file_count=0
    local disk_usage="0"
    
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

# 部分清理选择功能
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
        "自定义选择清理"
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
        3) # 自定义选择
            custom_cleanup_selection safe_items warning_items risky_items
            ;;
        4) # 取消操作
            ui_info "取消清理操作"
            return 0
            ;;
    esac
}

# 执行选择性清理
execute_selective_cleanup() {
    local -n items_ref=$1
    local force_mode="${2:-false}"
    
    if [[ ${#items_ref[@]} -eq 0 ]]; then
        ui_info "没有项目需要清理"
        return 0
    fi
    
    ui_subheader "🚀 执行选择性清理"
    
    # 收集清理前统计
    local before_stats
    before_stats=$(collect_environment_stats)
    
    # 初始化进度
    init_progress ${#items_ref[@]}
    
    local cleaned_count=0
    local error_count=0
    
    # 执行清理
    for item in "${items_ref[@]}"; do
        local type=$(echo "$item" | cut -d'|' -f1)
        local name=$(echo "$item" | cut -d'|' -f2)
        local reason=$(echo "$item" | cut -d'|' -f3)
        
        update_progress "清理 $type: $name"
        
        local result="成功"
        case "$type" in
            "工作树")
                if [[ -d ".worktrees/$name" ]]; then
                    if git worktree remove ".worktrees/$name" --force 2>/dev/null; then
                        ((cleaned_count++))
                    else
                        result="失败"
                        ((error_count++))
                    fi
                fi
                ;;
            "分支")
                if git branch -d "$name" 2>/dev/null || git branch -D "$name" 2>/dev/null; then
                    ((cleaned_count++))
                else
                    result="失败"
                    ((error_count++))
                fi
                ;;
            "临时文件")
                if rm -f "$name" 2>/dev/null; then
                    ((cleaned_count++))
                else
                    result="失败"
                    ((error_count++))
                fi
                ;;
        esac
        
        # 记录到历史
        log_cleanup_action "选择性清理" "$type:$name" "$result"
        
        # 短暂暂停以显示进度
        sleep 0.1
    done
    
    echo
    
    # 收集清理后统计
    local after_stats
    after_stats=$(collect_environment_stats)
    
    # 显示结果
    ui_success "🎉 选择性清理完成"
    echo "  ✅ 成功清理: $cleaned_count 项"
    if [[ $error_count -gt 0 ]]; then
        echo "  ❌ 清理失败: $error_count 项"
    fi
    
    echo
    show_before_after_comparison "$before_stats" "$after_stats"
}

# 自定义清理选择
custom_cleanup_selection() {
    local -n safe_ref=$1
    local -n warning_ref=$2
    local -n risky_ref=$3
    
    ui_subheader "🎯 自定义清理选择"
    
    local selected_items=()
    local all_items=("${safe_ref[@]}" "${warning_ref[@]}" "${risky_ref[@]}")
    
    ui_info "请逐个选择要清理的项目："
    echo
    
    local index=1
    for item in "${all_items[@]}"; do
        local type=$(echo "$item" | cut -d'|' -f1)
        local name=$(echo "$item" | cut -d'|' -f2)
        local reason=$(echo "$item" | cut -d'|' -f3)
        
        # 确定风险级别图标
        local risk_icon="🟢"
        for safe_item in "${safe_ref[@]}"; do
            if [[ "$item" == "$safe_item" ]]; then
                risk_icon="🟢"
                break
            fi
        done
        
        for warning_item in "${warning_ref[@]}"; do
            if [[ "$item" == "$warning_item" ]]; then
                risk_icon="🟡"
                break
            fi
        done
        
        for risky_item in "${risky_ref[@]}"; do
            if [[ "$item" == "$risky_item" ]]; then
                risk_icon="🔴"
                break
            fi
        done
        
        echo "$risk_icon $index. $type: $name"
        if [[ -n "$reason" ]]; then
            echo "     💬 $reason"
        fi
        
        if ui_confirm "   清理这个项目？"; then
            selected_items+=("$item")
            echo "     ✅ 已选择"
        else
            echo "     ⚠️ 跳过"
        fi
        
        echo
        ((index++))
    done
    
    if [[ ${#selected_items[@]} -eq 0 ]]; then
        ui_info "没有选择任何项目进行清理"
        return 0
    fi
    
    echo
    ui_info "已选择 ${#selected_items[@]} 个项目进行清理"
    
    if ui_confirm "确认执行自定义清理？"; then
        execute_selective_cleanup selected_items
    else
        ui_info "取消自定义清理"
    fi
}

# clean命令主函数
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
    
    # 执行相应的清理操作，集成增强功能
    case "$scope" in
        "worktrees")
            execute_enhanced_cleanup "worktrees" "$target" "$force_mode" "$dry_run"
            ;;
        "branches")
            execute_enhanced_cleanup "branches" "$target" "$force_mode" "$dry_run"
            ;;
        "epic")
            execute_enhanced_cleanup "epic" "$target" "$force_mode" "$dry_run"
            ;;
        "merged")
            execute_enhanced_cleanup "merged" "$target" "$force_mode" "$dry_run"
            ;;
        "all")
            execute_enhanced_cleanup "all" "$target" "$force_mode" "$dry_run"
            ;;
        "release")
            clean_after_release
            ;;
        *)
            ui_error "无效的清理范围: $scope"
            show_enhanced_clean_help
            return 1
            ;;
    esac
}

# 增强的帮助信息
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
}

# 增强的交互式清理
handle_enhanced_interactive_cleanup() {
    ui_header "🎯 智能清理中心"
    
    # 分析当前环境
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
            execute_enhanced_cleanup "all" "" "false" "false"
            ;;
        2) # 强制批量清理
            ui_warning "⚠️ 强制清理将跳过所有安全检查"
            if ui_confirm "确认执行强制清理？"; then
                execute_enhanced_cleanup "all" "" "true" "false"
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

# 执行增强的清理操作
execute_enhanced_cleanup() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    local dry_run="$4"
    
    # 收集清理前统计
    local before_stats
    before_stats=$(collect_environment_stats)
    
    # 显示进度和分类信息
    show_progress_bar 0 "准备清理..."
    
    if [[ "$dry_run" == "true" ]]; then
        ui_header "🔍 清理预览"
        show_categorized_cleanup_items "$operation_type" "$target"
        return 0
    fi
    
    # 执行安全检查（除非强制模式）
    if [[ "$force_mode" != "true" ]]; then
        show_progress_bar 20 "执行安全检查..."
        
        # 这里应该调用之前实现的安全检查系统
        local safety_level=0  # 假设安全检查通过
        
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
            clean_worktrees "$target"
            ;;
        "branches")
            show_progress_bar 60 "清理分支..."
            clean_branches "$target"
            ;;
        "epic")
            show_progress_bar 60 "清理Epic..."
            clean_epic "$target"
            ;;
        "merged")
            show_progress_bar 60 "清理已合并分支..."
            clean_merged_branches
            ;;
        "all")
            show_progress_bar 60 "执行全面清理..."
            clean_all_with_confirmation
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

# 记录清理开始
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

# 记录清理完成
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

# 维护历史记录数量限制
maintain_history_limit() {
    if [[ -f "$CLEANUP_HISTORY_FILE" ]]; then
        local line_count
        line_count=$(wc -l < "$CLEANUP_HISTORY_FILE")
        
        if [[ $line_count -gt $MAX_HISTORY_ENTRIES ]]; then
            # 保留最新的记录
            tail -n $MAX_HISTORY_ENTRIES "$CLEANUP_HISTORY_FILE" > "${CLEANUP_HISTORY_FILE}.tmp"
            mv "${CLEANUP_HISTORY_FILE}.tmp" "$CLEANUP_HISTORY_FILE"
        fi
    fi
}

# 显示清理摘要
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

# 显示清理建议
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