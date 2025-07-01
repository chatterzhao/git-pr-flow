#!/usr/bin/env bash

# Git PR Flow - clean命令实现
# 智能环境清理，支持工作树、分支、Epic级清理
# batch-operations: 优化批量操作体验，实现智能的 --all 和 --force 参数支持

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# ====== 批量操作核心功能 ======

# 全局变量用于跟踪清理统计
BATCH_STATS_WORKTREES_CLEANED=0
BATCH_STATS_WORKTREES_TOTAL=0
BATCH_STATS_BRANCHES_CLEANED=0
BATCH_STATS_BRANCHES_TOTAL=0
BATCH_STATS_EPICS_CLEANED=0
BATCH_STATS_EPICS_TOTAL=0
BATCH_STATS_FILES_CLEANED=0
BATCH_STATS_DISK_SAVED=""
BATCH_STATS_ERRORS=0

# 重置批量操作统计
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

# 执行批量清理操作
execute_batch_cleanup() {
    local operation_type="$1"    # all, worktrees, branches, epic, merged
    local target="$2"            # 目标名称（可选）
    local force_mode="$3"        # true/false
    local dry_run="$4"           # true/false
    
    ui_header "🧹 批量清理操作"
    
    reset_batch_stats
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 显示操作信息
    show_batch_operation_info "$operation_type" "$target" "$force_mode" "$dry_run"
    
    # 执行清理前检查
    if [[ "$dry_run" == "true" ]]; then
        execute_batch_preview "$operation_type" "$target" "$force_mode"
    else
        execute_batch_actual_cleanup "$operation_type" "$target" "$force_mode"
    fi
    
    # 记录结束时间并显示摘要
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    show_batch_summary "$operation_type" "$target" "$force_mode" "$dry_run" "$duration"
}

# 显示批量操作信息
show_batch_operation_info() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    local dry_run="$4"
    
    ui_subheader "📋 操作信息"
    
    echo "  🎯 操作类型: $operation_type"
    
    if [[ -n "$target" ]]; then
        echo "  🎭 目标: $target"
    fi
    
    if [[ "$force_mode" == "true" ]]; then
        echo "  ⚡ 模式: 强制清理（跳过安全检查）"
    else
        echo "  🛡️ 模式: 安全清理（含安全检查）"
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  👁️ 执行: 预览模式（不执行实际操作）"
    else
        echo "  🚀 执行: 实际清理"
    fi
    
    echo "  ⏰ 开始时间: $(date)"
    echo
}

# 执行批量预览
execute_batch_preview() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    
    ui_subheader "🔍 清理计划预览"
    
    case "$operation_type" in
        "all")
            preview_all_cleanup_operations "$force_mode"
            ;;
        "worktrees")
            preview_worktrees_cleanup "$target" "$force_mode"
            ;;
        "branches")
            preview_branches_cleanup "$target" "$force_mode"
            ;;
        "epic")
            preview_epic_cleanup "$target" "$force_mode"
            ;;
        "merged")
            preview_merged_branches_cleanup "$force_mode"
            ;;
    esac
}

# 预览所有清理操作
preview_all_cleanup_operations() {
    local force_mode="$1"
    
    echo "📊 全面清理计划："
    echo
    
    # 预览工作树清理
    echo "1️⃣ 工作树清理："
    local worktrees_count=0
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                local can_clean="🟢"
                local reason=""
                
                if [[ "$force_mode" != "true" ]]; then
                    local original_dir=$(pwd)
                    cd "$worktree" 2>/dev/null || continue
                    
                    if ! git diff-index --quiet HEAD 2>/dev/null; then
                        can_clean="🔴"
                        reason="(有未提交更改)"
                    elif ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                        can_clean="🔴"
                        reason="(有暂存更改)"
                    fi
                    
                    cd "$original_dir" || true
                fi
                
                echo "    $can_clean $worktree $reason"
                ((worktrees_count++))
            fi
        done
    fi
    BATCH_STATS["worktrees_total"]=$worktrees_count
    echo "    📊 工作树总数: $worktrees_count"
    echo
    
    # 预览分支清理
    echo "2️⃣ 分支清理："
    local branches_count=0
    local current_branch=$(git branch --show-current 2>/dev/null)
    local main_branches=("main" "master" "develop")
    
    # 检查已合并分支
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local merged_branches
            merged_branches=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" | sed 's/^[+ ]*//' || true)
            
            while IFS= read -r branch; do
                if [[ -n "$branch" && "$branch" != "$current_branch" ]]; then
                    local can_clean="🟢"
                    local reason="(已合并到 $main_branch)"
                    
                    # 检查是否有未推送提交
                    if git show-ref --verify --quiet "refs/remotes/origin/$branch" && [[ "$force_mode" != "true" ]]; then
                        local commits_ahead
                        commits_ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
                        if [[ "$commits_ahead" -gt 0 ]]; then
                            can_clean="🟡"
                            reason="(已合并，但有 $commits_ahead 个未推送提交)"
                        fi
                    fi
                    
                    echo "    $can_clean $branch $reason"
                    ((branches_count++))
                fi
            done <<< "$merged_branches"
            break  # 只需要检查一个存在的主分支
        fi
    done
    BATCH_STATS["branches_total"]=$branches_count
    echo "    📊 可清理分支数: $branches_count"
    echo
    
    # 预览临时文件清理
    echo "3️⃣ 临时文件清理："
    local temp_files=0
    for pattern in "epic-*-readiness-report.md" "CHANGELOG-*.md" "*.tmp" ".gpf-*.tmp"; do
        local files
        files=$(find . -name "$pattern" -type f 2>/dev/null || true)
        if [[ -n "$files" ]]; then
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    echo "    🧹 $file"
                    ((temp_files++))
                fi
            done <<< "$files"
        fi
    done
    BATCH_STATS["files_cleaned"]=$temp_files
    echo "    📊 临时文件数: $temp_files"
    echo
    
    # 显示潜在影响
    show_batch_preview_impact "$force_mode"
}

# 显示批量预览影响
show_batch_preview_impact() {
    local force_mode="$1"
    
    ui_subheader "💥 预期影响"
    
    local total_items=$((BATCH_STATS["worktrees_total"] + BATCH_STATS["branches_total"] + BATCH_STATS["files_cleaned"]))
    
    if [[ $total_items -eq 0 ]]; then
        ui_success "✨ 环境已经很干净，无需清理"
        return 0
    fi
    
    echo "  📊 总计将清理: $total_items 项资源"
    echo "  🏠 工作树: ${BATCH_STATS["worktrees_total"]} 个"
    echo "  🌿 分支: ${BATCH_STATS["branches_total"]} 个"
    echo "  📄 临时文件: ${BATCH_STATS["files_cleaned"]} 个"
    
    # 估算磁盘空间释放
    local estimated_size="0B"
    if [[ -d ".worktrees" ]]; then
        estimated_size=$(du -sh .worktrees 2>/dev/null | cut -f1 || echo "未知")
    fi
    echo "  💾 预计释放磁盘空间: $estimated_size"
    
    echo
    if [[ "$force_mode" == "true" ]]; then
        ui_warning "⚠️ 强制模式将跳过所有安全检查"
        ui_error "🚨 这可能导致未保存的工作丢失"
    else
        ui_success "🛡️ 安全模式将执行完整的安全检查"
    fi
    
    echo
    ui_info "执行命令:"
    if [[ "$force_mode" == "true" ]]; then
        ui_info "  gpf clean --all --force    # 强制执行清理"
    else
        ui_info "  gpf clean --all            # 安全执行清理"
    fi
}

# 预览工作树清理
preview_worktrees_cleanup() {
    local pattern="$1"
    local force_mode="$2"
    
    echo "🏠 工作树清理预览："
    echo
    
    local count=0
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                
                # 如果指定了模式，检查是否匹配
                if [[ -n "$pattern" && ! "$worktree_name" =~ $pattern ]]; then
                    continue
                fi
                
                local can_clean="🟢"
                local reason=""
                local branch_name
                
                # 从工作树路径提取分支名称
                if [[ "$worktree_name" =~ epic--(.+)--(.+) ]]; then
                    branch_name="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
                elif [[ "$worktree_name" =~ epic--(.+) ]]; then
                    branch_name="epic/${BASH_REMATCH[1]}"
                else
                    branch_name="unknown"
                fi
                
                if [[ "$force_mode" != "true" ]]; then
                    local original_dir=$(pwd)
                    cd "$worktree" 2>/dev/null || continue
                    
                    if ! git diff-index --quiet HEAD 2>/dev/null; then
                        can_clean="🔴"
                        reason="(有未提交更改)"
                    elif ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                        can_clean="🔴"
                        reason="(有暂存更改)"
                    elif [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                        can_clean="🟡"
                        reason="(有未跟踪文件)"
                    fi
                    
                    cd "$original_dir" || true
                fi
                
                echo "  $can_clean $worktree_name → $branch_name $reason"
                ((count++))
            fi
        done
    fi
    
    BATCH_STATS["worktrees_total"]=$count
    echo
    echo "📊 工作树总数: $count"
    
    if [[ $count -eq 0 ]]; then
        ui_info "✨ 没有找到需要清理的工作树"
    fi
}

# 预览分支清理
preview_branches_cleanup() {
    local pattern="$1"
    local force_mode="$2"
    
    echo "🌿 分支清理预览："
    echo
    
    local count=0
    local current_branch=$(git branch --show-current 2>/dev/null)
    local main_branches=("main" "master" "develop")
    
    # 检查已合并分支
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
                    
                    local can_clean="🟢"
                    local reason="(已合并到 $main_branch)"
                    
                    # 检查是否有未推送提交
                    if git show-ref --verify --quiet "refs/remotes/origin/$branch" && [[ "$force_mode" != "true" ]]; then
                        local commits_ahead
                        commits_ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
                        if [[ "$commits_ahead" -gt 0 ]]; then
                            can_clean="🟡"
                            reason="(已合并，但有 $commits_ahead 个未推送提交)"
                        fi
                    fi
                    
                    echo "  $can_clean $branch $reason"
                    ((count++))
                fi
            done <<< "$merged_branches"
            break  # 只需要检查一个存在的主分支
        fi
    done
    
    BATCH_STATS["branches_total"]=$count
    echo
    echo "📊 可清理分支数: $count"
    
    if [[ $count -eq 0 ]]; then
        ui_info "✨ 没有找到需要清理的分支"
    fi
}

# 预览Epic清理
preview_epic_cleanup() {
    local epic_name="$1"
    local force_mode="$2"
    
    echo "🚀 Epic清理预览 - $epic_name："
    echo
    
    # 检查Epic是否存在
    if ! git_branch_exists "epic/$epic_name"; then
        ui_error "Epic '$epic_name' 不存在"
        return 1
    fi
    
    # 预览功能分支
    local feature_branches
    feature_branches=$(git branch --format='%(refname:short)' | grep "^$epic_name/" || true)
    local feature_count=0
    
    if [[ -n "$feature_branches" ]]; then
        echo "  🌿 功能分支："
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                local can_clean="🟢"
                local reason="(Epic功能分支)"
                
                # 检查是否已合并
                if git merge-base --is-ancestor "$branch" "epic/$epic_name" 2>/dev/null; then
                    reason="(已合并到Epic主分支)"
                else
                    can_clean="🟡"
                    reason="(未合并到Epic主分支)"
                fi
                
                echo "    $can_clean $branch $reason"
                ((feature_count++))
            fi
        done <<< "$feature_branches"
    fi
    
    # 预览工作树
    local epic_worktrees
    epic_worktrees=$(find .worktrees -type d -name "epic--$epic_name*" 2>/dev/null || true)
    local worktree_count=0
    
    if [[ -n "$epic_worktrees" ]]; then
        echo "  🏠 工作树："
        while IFS= read -r worktree; do
            if [[ -n "$worktree" ]]; then
                local can_clean="🟢"
                local reason="(Epic工作树)"
                
                if [[ "$force_mode" != "true" ]]; then
                    local original_dir=$(pwd)
                    cd "$worktree" 2>/dev/null || continue
                    
                    if ! git diff-index --quiet HEAD 2>/dev/null; then
                        can_clean="🔴"
                        reason="(有未提交更改)"
                    fi
                    
                    cd "$original_dir" || true
                fi
                
                echo "    $can_clean $(basename "$worktree") $reason"
                ((worktree_count++))
            fi
        done <<< "$epic_worktrees"
    fi
    
    # 预览Epic主分支
    echo "  🚀 Epic主分支："
    echo "    🟢 epic/$epic_name (Epic主分支)"
    
    BATCH_STATS["worktrees_total"]=$worktree_count
    BATCH_STATS["branches_total"]=$((feature_count + 1))  # +1 for epic main branch
    
    echo
    echo "📊 Epic资源统计："
    echo "  🌿 功能分支: $feature_count 个"
    echo "  🏠 工作树: $worktree_count 个"
    echo "  🚀 Epic分支: 1 个"
}

# 预览已合并分支清理
preview_merged_branches_cleanup() {
    local force_mode="$1"
    
    echo "🌿 已合并分支清理预览："
    echo
    
    preview_branches_cleanup "" "$force_mode"
}

# 执行实际的批量清理
execute_batch_actual_cleanup() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    
    ui_subheader "🚀 执行清理操作"
    
    # 记录清理前的磁盘使用
    local disk_before=""
    if [[ -d ".worktrees" ]]; then
        disk_before=$(du -s .worktrees 2>/dev/null | cut -f1 || echo "0")
    fi
    
    case "$operation_type" in
        "all")
            execute_all_cleanup_operations "$force_mode"
            ;;
        "worktrees")
            execute_worktrees_cleanup "$target" "$force_mode"
            ;;
        "branches")
            execute_branches_cleanup "$target" "$force_mode"
            ;;
        "epic")
            execute_epic_cleanup "$target" "$force_mode"
            ;;
        "merged")
            execute_merged_branches_cleanup "$force_mode"
            ;;
    esac
    
    # 记录清理后的磁盘使用
    local disk_after=""
    if [[ -d ".worktrees" ]]; then
        disk_after=$(du -s .worktrees 2>/dev/null | cut -f1 || echo "0")
    else
        disk_after="0"
    fi
    
    # 计算释放的磁盘空间
    if [[ -n "$disk_before" && -n "$disk_after" ]]; then
        local disk_saved=$((disk_before - disk_after))
        if [[ $disk_saved -gt 0 ]]; then
            # 转换为人类可读格式
            if [[ $disk_saved -gt 1048576 ]]; then
                BATCH_STATS["disk_saved"]="$(($disk_saved / 1048576))GB"
            elif [[ $disk_saved -gt 1024 ]]; then
                BATCH_STATS["disk_saved"]="$(($disk_saved / 1024))MB"
            else
                BATCH_STATS["disk_saved"]="${disk_saved}KB"
            fi
        else
            BATCH_STATS["disk_saved"]="0B"
        fi
    fi
}

# 执行所有清理操作
execute_all_cleanup_operations() {
    local force_mode="$1"
    
    echo "🎯 执行全面清理："
    echo
    
    # 1. 清理工作树
    echo "1️⃣ 清理工作树..."
    local worktree_result
    worktree_result=$(execute_worktrees_cleanup "" "$force_mode" 2>&1)
    local worktree_exit_code=$?
    
    if [[ $worktree_exit_code -eq 0 ]]; then
        echo "  ✅ 工作树清理完成"
    else
        echo "  ❌ 工作树清理失败: $worktree_result"
        ((BATCH_STATS["errors"]++))
    fi
    
    # 2. 清理已合并分支
    echo "2️⃣ 清理已合并分支..."
    local branch_result
    branch_result=$(execute_merged_branches_cleanup "$force_mode" 2>&1)
    local branch_exit_code=$?
    
    if [[ $branch_exit_code -eq 0 ]]; then
        echo "  ✅ 分支清理完成"
    else
        echo "  ❌ 分支清理失败: $branch_result"
        ((BATCH_STATS["errors"]++))
    fi
    
    # 3. 清理临时文件
    echo "3️⃣ 清理临时文件..."
    local files_cleaned=0
    
    for pattern in "epic-*-readiness-report.md" "CHANGELOG-*.md" "*.tmp" ".gpf-*.tmp"; do
        local files
        files=$(find . -name "$pattern" -type f 2>/dev/null || true)
        if [[ -n "$files" ]]; then
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    if rm -f "$file" 2>/dev/null; then
                        echo "    🧹 删除: $file"
                        ((files_cleaned++))
                    else
                        echo "    ❌ 删除失败: $file"
                        ((BATCH_STATS["errors"]++))
                    fi
                fi
            done <<< "$files"
        fi
    done
    
    BATCH_STATS["files_cleaned"]=$files_cleaned
    
    if [[ $files_cleaned -gt 0 ]]; then
        echo "  ✅ 临时文件清理完成: $files_cleaned 个文件"
    else
        echo "  📝 没有找到需要清理的临时文件"
    fi
    
    echo
}

# 执行工作树清理
execute_worktrees_cleanup() {
    local pattern="$1"
    local force_mode="$2"
    
    local cleaned=0
    local total=0
    
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                
                # 如果指定了模式，检查是否匹配
                if [[ -n "$pattern" && ! "$worktree_name" =~ $pattern ]]; then
                    continue
                fi
                
                ((total++))
                
                # 检查是否可以安全清理
                local can_clean=true
                if [[ "$force_mode" != "true" ]]; then
                    local original_dir=$(pwd)
                    cd "$worktree" 2>/dev/null || continue
                    
                    if ! git diff-index --quiet HEAD 2>/dev/null || ! git diff-index --cached --quiet HEAD 2>/dev/null; then
                        can_clean=false
                    fi
                    
                    cd "$original_dir" || true
                fi
                
                if [[ "$can_clean" == "true" || "$force_mode" == "true" ]]; then
                    if git worktree remove "$worktree" --force 2>/dev/null; then
                        echo "    ✅ 清理: $worktree_name"
                        ((cleaned++))
                    else
                        echo "    ❌ 清理失败: $worktree_name"
                        ((BATCH_STATS["errors"]++))
                    fi
                else
                    echo "    ⚠️ 跳过: $worktree_name (有未提交更改)"
                fi
            fi
        done
    fi
    
    BATCH_STATS["worktrees_cleaned"]=$cleaned
    BATCH_STATS["worktrees_total"]=$total
    
    return 0
}

# 执行分支清理
execute_branches_cleanup() {
    local pattern="$1"
    local force_mode="$2"
    
    local cleaned=0
    local total=0
    local current_branch=$(git branch --show-current 2>/dev/null)
    local main_branches=("main" "master" "develop")
    
    # 清理已合并分支
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
                    
                    ((total++))
                    
                    # 检查是否可以安全清理
                    local can_clean=true
                    if [[ "$force_mode" != "true" ]]; then
                        # 检查是否有未推送提交
                        if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                            local commits_ahead
                            commits_ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
                            if [[ "$commits_ahead" -gt 0 ]]; then
                                can_clean=false
                            fi
                        fi
                    fi
                    
                    if [[ "$can_clean" == "true" || "$force_mode" == "true" ]]; then
                        if git branch -d "$branch" 2>/dev/null; then
                            echo "    ✅ 删除: $branch"
                            ((cleaned++))
                        elif git branch -D "$branch" 2>/dev/null; then
                            echo "    ⚡ 强制删除: $branch"
                            ((cleaned++))
                        else
                            echo "    ❌ 删除失败: $branch"
                            ((BATCH_STATS["errors"]++))
                        fi
                    else
                        echo "    ⚠️ 跳过: $branch (有未推送提交)"
                    fi
                fi
            done <<< "$merged_branches"
            break  # 只需要检查一个存在的主分支
        fi
    done
    
    BATCH_STATS["branches_cleaned"]=$cleaned
    BATCH_STATS["branches_total"]=$total
    
    return 0
}

# 执行Epic清理
execute_epic_cleanup() {
    local epic_name="$1"
    local force_mode="$2"
    
    if ! git_branch_exists "epic/$epic_name"; then
        echo "    ❌ Epic '$epic_name' 不存在"
        ((BATCH_STATS["errors"]++))
        return 1
    fi
    
    local cleaned_branches=0
    local cleaned_worktrees=0
    
    # 清理功能分支
    local feature_branches
    feature_branches=$(git branch --format='%(refname:short)' | grep "^$epic_name/" || true)
    
    if [[ -n "$feature_branches" ]]; then
        echo "    🌿 清理功能分支:"
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                if git branch -D "$branch" 2>/dev/null; then
                    echo "      ✅ 删除: $branch"
                    ((cleaned_branches++))
                else
                    echo "      ❌ 删除失败: $branch"
                    ((BATCH_STATS["errors"]++))
                fi
            fi
        done <<< "$feature_branches"
    fi
    
    # 清理工作树
    local epic_worktrees
    epic_worktrees=$(find .worktrees -type d -name "epic--$epic_name*" 2>/dev/null || true)
    
    if [[ -n "$epic_worktrees" ]]; then
        echo "    🏠 清理工作树:"
        while IFS= read -r worktree; do
            if [[ -n "$worktree" ]]; then
                local worktree_name=$(basename "$worktree")
                if git worktree remove "$worktree" --force 2>/dev/null; then
                    echo "      ✅ 清理: $worktree_name"
                    ((cleaned_worktrees++))
                else
                    echo "      ❌ 清理失败: $worktree_name"
                    ((BATCH_STATS["errors"]++))
                fi
            fi
        done <<< "$epic_worktrees"
    fi
    
    # 清理Epic主分支
    echo "    🚀 清理Epic主分支:"
    if git branch -D "epic/$epic_name" 2>/dev/null; then
        echo "      ✅ 删除: epic/$epic_name"
        ((cleaned_branches++))
    else
        echo "      ❌ 删除失败: epic/$epic_name"
        ((BATCH_STATS["errors"]++))
    fi
    
    BATCH_STATS["branches_cleaned"]=$cleaned_branches
    BATCH_STATS["worktrees_cleaned"]=$cleaned_worktrees
    BATCH_STATS["epics_cleaned"]=1
    
    return 0
}

# 执行已合并分支清理
execute_merged_branches_cleanup() {
    local force_mode="$1"
    
    execute_branches_cleanup "" "$force_mode"
}

# 显示批量操作摘要
show_batch_summary() {
    local operation_type="$1"
    local target="$2"
    local force_mode="$3"
    local dry_run="$4"
    local duration="$5"
    
    echo
    ui_header "📊 批量操作摘要"
    
    # 基本信息
    ui_subheader "📋 操作信息"
    echo "  🎯 操作类型: $operation_type"
    if [[ -n "$target" ]]; then
        echo "  🎭 目标: $target"
    fi
    echo "  ⚡ 模式: $(if [[ "$force_mode" == "true" ]]; then echo "强制清理"; else echo "安全清理"; fi)"
    echo "  👁️ 执行类型: $(if [[ "$dry_run" == "true" ]]; then echo "预览模式"; else echo "实际执行"; fi)"
    echo "  ⏱️ 用时: ${duration}秒"
    echo
    
    # 清理统计
    ui_subheader "📊 清理统计"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  📋 预览结果："
        echo "    🏠 工作树: ${BATCH_STATS["worktrees_total"]} 个待清理"
        echo "    🌿 分支: ${BATCH_STATS["branches_total"]} 个待清理"
        echo "    📄 临时文件: ${BATCH_STATS["files_cleaned"]} 个待清理"
        
        local total_items=$((BATCH_STATS["worktrees_total"] + BATCH_STATS["branches_total"] + BATCH_STATS["files_cleaned"]))
        echo "    📊 总计: $total_items 项资源待清理"
        
    else
        echo "  ✅ 实际清理结果："
        echo "    🏠 工作树: ${BATCH_STATS["worktrees_cleaned"]}/${BATCH_STATS["worktrees_total"]} 个已清理"
        echo "    🌿 分支: ${BATCH_STATS["branches_cleaned"]}/${BATCH_STATS["branches_total"]} 个已清理"
        echo "    📄 临时文件: ${BATCH_STATS["files_cleaned"]} 个已清理"
        
        if [[ ${BATCH_STATS["epics_cleaned"]} -gt 0 ]]; then
            echo "    🚀 Epic: ${BATCH_STATS["epics_cleaned"]} 个已清理"
        fi
        
        local total_cleaned=$((BATCH_STATS["worktrees_cleaned"] + BATCH_STATS["branches_cleaned"] + BATCH_STATS["files_cleaned"] + BATCH_STATS["epics_cleaned"]))
        echo "    📊 总计: $total_cleaned 项资源已清理"
        
        if [[ -n "${BATCH_STATS["disk_saved"]}" && "${BATCH_STATS["disk_saved"]}" != "0B" ]]; then
            echo "    💾 释放磁盘空间: ${BATCH_STATS["disk_saved"]}"
        fi
        
        if [[ ${BATCH_STATS["errors"]} -gt 0 ]]; then
            echo "    ❌ 错误数: ${BATCH_STATS["errors"]} 个"
        fi
    fi
    
    echo
    
    # 操作结果评估
    if [[ "$dry_run" == "true" ]]; then
        ui_subheader "💡 下一步建议"
        
        local total_items=$((BATCH_STATS["worktrees_total"] + BATCH_STATS["branches_total"] + BATCH_STATS["files_cleaned"]))
        
        if [[ $total_items -eq 0 ]]; then
            ui_success "✨ 环境已经很干净，无需清理"
        else
            ui_info "根据预览结果，建议执行以下命令："
            
            case "$operation_type" in
                "all")
                    if [[ "$force_mode" == "true" ]]; then
                        ui_info "  gpf clean --all --force    # 强制清理所有资源"
                    else
                        ui_info "  gpf clean --all            # 安全清理所有资源"
                    fi
                    ;;
                "worktrees")
                    if [[ -n "$target" ]]; then
                        ui_info "  gpf clean worktrees $target    # 清理匹配的工作树"
                    else
                        ui_info "  gpf clean worktrees             # 清理所有工作树"
                    fi
                    ;;
                "branches")
                    if [[ -n "$target" ]]; then
                        ui_info "  gpf clean branches $target     # 清理匹配的分支"
                    else
                        ui_info "  gpf clean branches              # 清理已合并分支"
                    fi
                    ;;
                "epic")
                    ui_info "  gpf clean epic $target          # 清理指定Epic"
                    ;;
                "merged")
                    ui_info "  gpf clean merged                # 清理已合并分支"
                    ;;
            esac
        fi
        
    else
        ui_subheader "🎉 操作完成"
        
        local total_cleaned=$((BATCH_STATS["worktrees_cleaned"] + BATCH_STATS["branches_cleaned"] + BATCH_STATS["files_cleaned"] + BATCH_STATS["epics_cleaned"]))
        
        if [[ $total_cleaned -eq 0 && ${BATCH_STATS["errors"]} -eq 0 ]]; then
            ui_info "✨ 环境已经很干净，无需清理"
        elif [[ ${BATCH_STATS["errors"]} -eq 0 ]]; then
            ui_success "🎉 清理操作成功完成！环境已优化"
        else
            ui_warning "⚠️ 清理操作完成，但存在 ${BATCH_STATS["errors"]} 个错误"
            ui_info "请检查上面的错误信息并手动处理"
        fi
        
        # 显示后续建议
        if [[ $total_cleaned -gt 0 ]]; then
            echo
            ui_info "建议后续操作："
            ui_info "  git gc                       # 清理Git对象以进一步释放空间"
            ui_info "  gpf clean --dry-run          # 检查是否还有其他可清理项目"
        fi
    fi
    
    echo
}

# clean命令主函数 - 集成批量操作系统
cmd_clean() {
    local dry_run=false
    local force_mode=false
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
                show_batch_clean_help
                return 1
                ;;
            *)
                if [[ -z "$scope" ]]; then
                    ui_error "无效的清理类型: $1"
                    show_batch_clean_help
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
        show_batch_clean_help
        return 0
    fi
    
    # 处理只有 --dry-run 参数的情况
    if [[ -z "$scope" && "$dry_run" == "true" ]]; then
        execute_batch_cleanup "all" "" "$force_mode" "$dry_run"
        return $?
    fi
    
    # 无参数时显示智能引导
    if [[ -z "$scope" ]]; then
        show_batch_guided_options
        return 0
    fi
    
    # 执行批量清理操作
    case "$scope" in
        "worktrees")
            execute_batch_cleanup "worktrees" "$target" "$force_mode" "$dry_run"
            ;;
        "branches")
            execute_batch_cleanup "branches" "$target" "$force_mode" "$dry_run"
            ;;
        "epic")
            if [[ -z "$target" ]]; then
                ui_error "清理Epic需要指定Epic名称"
                ui_info "用法: gpf clean epic <epic-name>"
                return 1
            fi
            execute_batch_cleanup "epic" "$target" "$force_mode" "$dry_run"
            ;;
        "merged")
            execute_batch_cleanup "merged" "" "$force_mode" "$dry_run"
            ;;
        "all")
            execute_batch_cleanup "all" "" "$force_mode" "$dry_run"
            ;;
        "release")
            execute_batch_cleanup "release" "" "$force_mode" "$dry_run"
            ;;
        *)
            # 这应该不会到达，因为参数解析已经处理了
            handle_clean_interactive
            ;;
    esac
}

# ====== 批量操作辅助功能 ======

# 显示批量清理帮助信息
show_batch_clean_help() {
    cat << EOF
GPF Clean命令 - 智能批量清理工具

用法:
  gpf clean [选项] [类型] [目标]

选项:
  --dry-run             预览清理计划，不执行实际操作
  --all                 清理所有类型的资源
  --force               强制清理，跳过安全检查
  --help, -h            显示此帮助信息

清理类型:
  worktrees [pattern]   清理工作树（pattern可选，支持通配符）
  branches [pattern]    清理分支（pattern可选，支持通配符）
  epic <epic-name>      清理指定Epic（必须指定Epic名称）
  merged                清理已合并分支

特殊操作:
  --release             发布后清理

批量操作示例:
  gpf clean                           # 显示智能引导和环境分析
  gpf clean --dry-run                 # 预览所有清理计划
  gpf clean --all                     # 安全清理所有资源
  gpf clean --all --force             # 强制清理所有资源
  gpf clean --all --dry-run           # 预览完整清理计划
  gpf clean worktrees                 # 批量清理工作树
  gpf clean worktrees epic--test*     # 清理匹配模式的工作树
  gpf clean branches feature/*        # 清理feature分支
  gpf clean epic test                 # 清理test Epic（全部资源）
  gpf clean merged                    # 批量清理已合并分支

批量操作特性:
  📊 详细的预览和影响分析
  ⏱️ 操作计时和性能统计
  💾 磁盘空间释放统计
  📋 完整的清理摘要报告
  🛡️ 智能安全检查和确认
  🎯 支持模式匹配和过滤

安全级别:
  🟢 安全操作：已合并分支、未使用工作树
  🟡 警告操作：有未推送提交但可清理
  🔴 危险操作：强制清理、跳过安全检查

EOF
}

# 显示批量操作引导选项
show_batch_guided_options() {
    ui_header "🧹 智能批量清理引导"
    
    # 快速环境分析
    echo "正在分析清理环境..."
    
    # 统计可清理资源
    local worktree_count=0
    local branch_count=0
    local temp_file_count=0
    
    # 统计工作树
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                ((worktree_count++))
            fi
        done
    fi
    
    # 统计已合并分支
    local main_branches=("main" "master" "develop")
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local merged_branches
            merged_branches=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" | wc -l || echo "0")
            branch_count=$merged_branches
            break
        fi
    done
    
    # 统计临时文件
    for pattern in "epic-*-readiness-report.md" "CHANGELOG-*.md" "*.tmp" ".gpf-*.tmp"; do
        local files
        files=$(find . -name "$pattern" -type f 2>/dev/null || true)
        if [[ -n "$files" ]]; then
            temp_file_count=$((temp_file_count + $(echo "$files" | wc -l)))
        fi
    done
    
    echo
    ui_subheader "📊 环境分析结果"
    echo "  🏠 工作树: $worktree_count 个"
    echo "  🌿 已合并分支: $branch_count 个"
    echo "  📄 临时文件: $temp_file_count 个"
    
    local total_items=$((worktree_count + branch_count + temp_file_count))
    echo "  📋 总计可清理: $total_items 项资源"
    
    if [[ -d ".worktrees" ]]; then
        local disk_usage
        disk_usage=$(du -sh .worktrees 2>/dev/null | cut -f1 || echo "未知")
        echo "  💾 工作树占用: $disk_usage"
    fi
    
    echo
    ui_subheader "💡 推荐的批量操作"
    
    if [[ $total_items -eq 0 ]]; then
        ui_success "✨ 环境已经很干净，无需清理"
        echo
        ui_info "🔍 可用的检查命令："
        ui_info "  gpf clean --dry-run          # 深度分析可清理项目"
        ui_info "  gpf status                   # 查看项目状态"
        
    elif [[ $total_items -le 5 ]]; then
        ui_info "🟢 环境较为干净，建议选择性清理："
        echo
        ui_info "📋 预览和选择："
        ui_info "  gpf clean --dry-run          # 查看详细清理计划"
        ui_info "  gpf clean worktrees          # 只清理工作树 ($worktree_count 个)"
        ui_info "  gpf clean branches           # 只清理已合并分支 ($branch_count 个)"
        echo
        ui_info "🎯 一键清理："
        ui_info "  gpf clean --all              # 安全清理所有资源"
        
    else
        ui_warning "🟡 发现较多可清理项目，建议批量清理："
        echo
        ui_info "🔍 建议先预览："
        ui_info "  gpf clean --all --dry-run    # 预览完整清理计划"
        echo
        ui_info "🧹 批量清理："
        ui_info "  gpf clean --all              # 安全批量清理"
        ui_info "  gpf clean --all --force      # 强制批量清理（谨慎使用）"
        echo
        ui_info "🎯 分类清理："
        ui_info "  gpf clean worktrees          # 批量清理工作树"
        ui_info "  gpf clean branches           # 批量清理分支"
    fi
    
    echo
    ui_info "📖 详细帮助：gpf clean --help"
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
    
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*; do
            if [[ -d "$worktree" ]]; then
                local original_dir=$(pwd)
                cd "$worktree" 2>/dev/null || continue
                
                if git diff-index --quiet HEAD 2>/dev/null && git diff-index --cached --quiet HEAD 2>/dev/null; then
                    ((count++))
                fi
                
                cd "$original_dir" || true
            fi
        done
    fi
    
    echo "$count"
}

# 统计已合并分支
count_merged_branches() {
    local count=0
    local main_branches=("main" "master" "develop")
    
    for main_branch in "${main_branches[@]}"; do
        if git_branch_exists "$main_branch"; then
            local merged_branches
            merged_branches=$(git branch --merged "$main_branch" 2>/dev/null | grep -v -E "(${main_branch}|\*)" | wc -l || echo "0")
            count=$merged_branches
            break
        fi
    done
    
    echo "$count"
}

# 清理工作树（兼容旧接口）
clean_worktrees() {
    local pattern="${1:-}"
    execute_batch_cleanup "worktrees" "$pattern" "false" "false"
}

# 清理分支（兼容旧接口）
clean_branches() {
    local pattern="${1:-}"
    execute_batch_cleanup "branches" "$pattern" "false" "false"
}

# 清理Epic（兼容旧接口）
clean_epic() {
    local epic_name="${1:-}"
    if [[ -z "$epic_name" ]]; then
        ui_error "清理Epic需要指定Epic名称"
        return 1
    fi
    execute_batch_cleanup "epic" "$epic_name" "false" "false"
}

# 清理已合并分支（兼容旧接口）
clean_merged_branches() {
    execute_batch_cleanup "merged" "" "false" "false"
}

# 全面清理确认（兼容旧接口）
clean_all_with_confirmation() {
    execute_batch_cleanup "all" "" "false" "false"
}

# 发布后清理（兼容旧接口）
clean_after_release() {
    execute_batch_cleanup "release" "" "false" "false"
}

# 显示详细清理状态
show_detailed_cleanup_status() {
    ui_header "详细清理状态分析"
    
    # 执行详细预览
    execute_batch_cleanup "all" "" "false" "true"
}
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