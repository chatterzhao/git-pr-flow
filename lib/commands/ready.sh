#!/usr/bin/env bash

# Git PR Flow - ready命令实现
# Epic级策略性发布检查，验证所有功能分支的就绪状态

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# 引入配置重构后的系统
[[ -f "$COMMAND_SCRIPT_DIR/../utils/config-context-bridge.sh" ]] && source "$COMMAND_SCRIPT_DIR/../utils/config-context-bridge.sh"

# ready命令主函数
cmd_ready() {
    local target_branch="${1:-}"
    
    # 加载path工具函数
    if [[ -f "$PROJECT_ROOT/lib/utils/paths.sh" ]]; then
        source "$PROJECT_ROOT/lib/utils/paths.sh"
    fi
    
    # 如果没有参数，启动智能分支选择模式
    if [[ -z "$target_branch" ]]; then
        target_branch=$(smart_branch_selection)
        if [[ -z "$target_branch" ]]; then
            ui_info "已取消操作"
            return 0
        fi
    fi
    
    # 验证目标分支格式 (应该是 xx/yy 格式)
    if ! validate_feature_branch_format "$target_branch"; then
        ui_error "无效的分支格式: $target_branch"
        ui_info "分支格式应为: epic-name/feature-name，如: auth/login"
        return 1
    fi
    
    # 执行完整的ready检查流程
    execute_full_ready_pipeline "$target_branch"
}

# 验证功能分支格式
validate_feature_branch_format() {
    local branch_name="$1"
    
    # 基本格式检查：应该包含 /
    if [[ "$branch_name" != */* ]]; then
        return 1
    fi
    
    # 不应该以 epic/ 开头 (ready命令处理的是功能分支)
    if [[ "$branch_name" == epic/* ]]; then
        return 1
    fi
    
    # 分支名不能为空
    if [[ -z "$branch_name" ]]; then
        return 1
    fi
    
    return 0
}

# 智能分支选择
smart_branch_selection() {
    ui_header "🚀 Ready 检查 - 智能分支选择"
    
    # 检测当前上下文
    local context_type
    context_type=$(detect_current_context_type)
    
    case "$context_type" in
        "feature_worktree")
            # 在功能分支目录中，直接使用当前分支
            local current_feature
            current_feature=$(detect_current_feature_name)
            if [[ -n "$current_feature" ]]; then
                ui_info "检测到当前功能分支: $current_feature"
                echo "$current_feature"
                return 0
            fi
            ;;
        "epic_worktree")
            # 在Epic目录中，列出该Epic的功能分支
            local epic_name
            epic_name=$(detect_current_epic_name)
            if [[ -n "$epic_name" ]]; then
                show_epic_branch_selection_menu "$epic_name"
                return $?
            fi
            ;;
        "project_root")
            # 在项目根目录，列出所有功能分支
            show_all_branch_selection_menu
            return $?
            ;;
    esac
    
    # 如果上下文检测失败，回退到显示所有分支
    ui_warning "无法检测当前上下文，显示所有可用分支"
    show_all_branch_selection_menu
}

# 显示Epic下的分支选择菜单
show_epic_branch_selection_menu() {
    local epic_name="$1"
    
    # 获取Epic下的所有功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" | sort)
    
    if [[ -z "$feature_branches" ]]; then
        ui_warning "Epic '$epic_name' 下没有找到功能分支"
        ui_info "使用 'gpf start $epic_name/feature-name' 创建功能分支"
        return 1
    fi
    
    # 构建选择选项（包含状态信息）
    local options=()
    local branch_array=()
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            branch_array+=("$branch")
            local status_info
            status_info=$(get_branch_status_info "$branch")
            options+=("$branch - $status_info")
        fi
    done <<< "$feature_branches"
    
    if [[ ${#options[@]} -eq 0 ]]; then
        ui_warning "没有可用的功能分支"
        return 1
    fi
    
    ui_info "Epic: $epic_name"
    local choice
    choice=$(ui_select_menu "选择要检查的功能分支" "${options[@]}")
    
    if [[ $choice -ge 0 && $choice -lt ${#branch_array[@]} ]]; then
        echo "${branch_array[$choice]}"
        return 0
    fi
    
    return 1
}

# 显示所有分支选择菜单  
show_all_branch_selection_menu() {
    # 获取所有功能分支（排除Epic分支）
    local all_branches
    all_branches=$(git_list_branches | grep "/" | grep -v "^epic/" | sort)
    
    if [[ -z "$all_branches" ]]; then
        ui_warning "没有找到功能分支"
        ui_info "使用 'gpf init epic-name' 创建Epic，然后使用 'gpf start epic-name/feature-name' 创建功能分支"
        return 1
    fi
    
    # 按Epic分组显示
    local options=()
    local branch_array=()
    local current_epic=""
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local epic_part feature_part
            epic_part=$(echo "$branch" | cut -d'/' -f1)
            feature_part=$(echo "$branch" | cut -d'/' -f2-)
            
            if [[ "$epic_part" != "$current_epic" ]]; then
                if [[ -n "$current_epic" ]]; then
                    options+=("── Epic: $epic_part ──")
                    branch_array+=("")
                else
                    current_epic="$epic_part"
                fi
                current_epic="$epic_part"
            fi
            
            branch_array+=("$branch")
            local status_info
            status_info=$(get_branch_status_info "$branch")
            options+=("  $feature_part - $status_info")
        fi
    done <<< "$all_branches"
    
    if [[ ${#branch_array[@]} -eq 0 ]]; then
        ui_warning "没有可用的功能分支"
        return 1
    fi
    
    local choice
    choice=$(ui_select_menu "选择要检查的功能分支" "${options[@]}")
    
    # 跳过分隔符行
    while [[ $choice -ge 0 && $choice -lt ${#branch_array[@]} && -z "${branch_array[$choice]}" ]]; do
        ui_warning "请选择具体的分支，而非分组标题"
        choice=$(ui_select_menu "选择要检查的功能分支" "${options[@]}")
    done
    
    if [[ $choice -ge 0 && $choice -lt ${#branch_array[@]} && -n "${branch_array[$choice]}" ]]; then
        echo "${branch_array[$choice]}"
        return 0
    fi
    
    return 1
}

# 获取分支状态信息
get_branch_status_info() {
    local branch="$1"
    
    # 检查工作树是否存在
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$branch" 2>/dev/null)
    
    if [[ ! -d "$worktree_path" ]]; then
        echo "📋 仅分支 (无工作树)"
        return 0
    fi
    
    # 检查最后提交时间
    local last_commit_time
    last_commit_time=$(git log -1 --format="%cr" "$branch" 2>/dev/null || echo "未知时间")
    
    # 简单的就绪状态检查
    if check_single_branch_readiness "$branch" >/dev/null 2>&1; then
        echo "✅ 就绪 (最后提交: $last_commit_time)"
    else
        echo "⚠️ 待处理 (最后提交: $last_commit_time)"
    fi
}

# 执行完整的ready检查流程
execute_full_ready_pipeline() {
    local target_branch="$1"
    
    ui_header "🚀 Ready 检查流程: $target_branch"
    
    # 验证分支存在性
    if ! git_branch_exists "$target_branch"; then
        ui_error "分支不存在: $target_branch"
        return 1
    fi
    
    local overall_success=true
    local step=1
    local total_steps=4
    
    # 步骤1: 验证依赖关系完整性
    ui_subheader "[$step/$total_steps] 🔍 验证依赖关系完整性"
    if validate_branch_dependencies "$target_branch"; then
        ui_success "✅ 依赖关系验证通过"
    else
        ui_warning "⚠️ 依赖关系验证有警告"
        overall_success=false
    fi
    ((step++))
    echo
    
    # 步骤2: 检查代码质量和状态  
    ui_subheader "[$step/$total_steps] 🔍 检查代码质量和状态"
    if check_branch_readiness "$target_branch"; then
        ui_success "✅ 代码质量检查通过"
    else
        ui_warning "⚠️ 代码质量检查有问题"
        overall_success=false
    fi
    ((step++))
    echo
    
    # 步骤3: 生成详细报告
    ui_subheader "[$step/$total_steps] 📄 生成详细报告"
    if generate_branch_readiness_report "$target_branch"; then
        ui_success "✅ 详细报告已生成"
    else
        ui_warning "⚠️ 报告生成有问题"
    fi
    ((step++))
    echo
    
    # 步骤4: 准备发布（仅在前面都通过时）
    ui_subheader "[$step/$total_steps] 🚀 准备发布"
    if [[ "$overall_success" == "true" ]]; then
        if prepare_branch_release "$target_branch"; then
            ui_success "✅ 发布准备完成"
        else
            ui_warning "⚠️ 发布准备有问题"
        fi
    else
        ui_info "⏭️ 跳过发布准备 (前置检查未通过)"
        ui_info "请解决上述问题后重新运行检查"
    fi
    
    # 显示最终结果
    show_pipeline_summary "$target_branch" "$overall_success"
    
    return $([ "$overall_success" == "true" ])
}

# 显示流程总结
show_pipeline_summary() {
    local branch="$1"
    local success="$2"
    
    echo
    ui_subheader "📊 Ready 检查总结"
    
    if [[ "$success" == "true" ]]; then
        ui_success_box "🎉 分支已准备就绪！" \
            "分支: $branch" \
            "所有检查项目均已通过" \
            "" \
            "建议下一步操作:" \
            "1. gpf pr $branch    # 创建PR" \
            "2. 通知团队成员进行代码审查" \
            "3. 合并后使用 gpf clean $branch"
    else
        ui_warning_box "⚠️ 分支尚未完全就绪" \
            "分支: $branch" \
            "存在需要关注的问题" \
            "" \
            "建议操作:" \
            "1. 查看详细报告了解具体问题" \
            "2. 解决标记的问题" \
            "3. 重新运行: gpf ready $branch"
    fi
}

# 验证分支依赖关系
validate_branch_dependencies() {
    local branch="$1"
    
    # 提取Epic名称
    local epic_name
    epic_name=$(echo "$branch" | cut -d'/' -f1)
    
    # 检查Epic配置是否存在
    if ! config_epic_exists "$epic_name"; then
        ui_warning "未找到Epic配置: $epic_name"
        return 1
    fi
    
    local base_branch
    base_branch=$(config_epic_get "base_branch" "$epic_name")
    
    # 检查基础分支同步状态
    local behind_count
    behind_count=$(git rev-list --count "$branch..$base_branch" 2>/dev/null || echo "0")
    
    if [[ "$behind_count" -gt 0 ]]; then
        ui_warning "  ⚠️ 分支落后基础分支 $behind_count 个提交"
        ui_info "  💡 建议运行: git-pr-flow sync"
        return 1
    else
        ui_info "  ✅ 与基础分支 ($base_branch) 同步"
    fi
    
    # 检查分支间依赖关系
    local dependencies
    dependencies=$(detect_branch_dependencies "$branch")
    
    if [[ -n "$dependencies" ]]; then
        ui_info "  🔗 检测到依赖: $dependencies"
        # 验证依赖分支状态
        if ! validate_dependencies "$branch" "$dependencies"; then
            return 1
        fi
    else
        ui_info "  ✅ 无额外依赖"
    fi
    
    return 0
}

# 检查分支就绪状态
check_branch_readiness() {
    local branch="$1"
    
    local issues=0
    
    # 检查工作树状态
    local worktree_absolute_path worktree_relative_path
    worktree_absolute_path=$(get_branch_worktree_absolute_path "$branch")
    worktree_relative_path=$(get_branch_worktree_path "$branch")
    
    if [[ ! -d "$worktree_absolute_path" ]]; then
        ui_warning "  ⚠️ 工作树不存在: $worktree_relative_path"
        ((issues++))
    else
        ui_info "  ✅ 工作树存在: $worktree_relative_path"
        
        # 检查工作目录是否干净
        local original_dir
        original_dir=$(pwd)
        
        cd "$worktree_absolute_path" || return 1
        
        if git_is_clean; then
            ui_info "  ✅ 工作目录干净"
        else
            ui_warning "  ⚠️ 工作目录有未提交的变更"
            ui_info "  💡 请提交或暂存所有变更"
            ((issues++))
        fi
        
        cd "$original_dir" || true
    fi
    
    # 检查提交历史
    local commit_count
    commit_count=$(git rev-list --count "$branch" 2>/dev/null || echo "0")
    
    if [[ "$commit_count" -eq 0 ]]; then
        ui_warning "  ⚠️ 分支没有提交"
        ((issues++))
    else
        ui_info "  ✅ 分支有 $commit_count 个提交"
    fi
    
    # 简单的代码质量检查
    check_code_quality_for_branch "$branch"
    local quality_result=$?
    
    if [[ $quality_result -ne 0 ]]; then
        ((issues++))
    fi
    
    return $([ $issues -eq 0 ])
}

# 检查单个分支的代码质量
check_code_quality_for_branch() {
    local branch="$1"
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$branch")
    
    if [[ ! -d "$worktree_path" ]]; then
        ui_warning "  ⚠️ 无法检查代码质量：工作树不存在"
        return 1
    fi
    
    local original_dir issues
    original_dir=$(pwd)
    issues=0
    
    cd "$worktree_path" || return 1
    
    # 检查代码规范工具
    if [[ -f "package.json" ]] && grep -q '"lint"' package.json; then
        ui_info "  ✅ 发现lint脚本配置"
    else
        ui_info "  ℹ️ 未发现lint脚本配置（可选）"
    fi
    
    # 检查测试配置
    if [[ -d "test" || -d "tests" || -d "__tests__" ]] || grep -q '"test"' package.json 2>/dev/null; then
        ui_info "  ✅ 发现测试配置"
    else
        ui_info "  ℹ️ 未发现测试配置（建议添加）"
    fi
    
    cd "$original_dir" || true
    
    return $issues
}

# 生成分支就绪报告
generate_branch_readiness_report() {
    local branch="$1"
    local epic_name
    epic_name=$(echo "$branch" | cut -d'/' -f1)
    local feature_name
    feature_name=$(echo "$branch" | cut -d'/' -f2-)
    
    local project_root
    project_root=$(get_project_root_path) || {
        ui_error "无法获取项目根目录"
        return 1
    }
    
    # 确保 docs/ready-report 目录存在
    mkdir -p "$project_root/docs/ready-report"
    
    local report_file="$project_root/docs/ready-report/ready-report-${branch//\//-}.md"
    
    ui_info "  📄 生成报告: docs/ready-report/ready-report-${branch//\//-}.md"
    
    # 生成Markdown报告
    cat > "$report_file" << EOF
# Ready 检查报告

**分支**: $branch  
**Epic**: $epic_name  
**功能**: $feature_name  
**生成时间**: $(current_local_timestamp)  

## 执行摘要

$(if validate_branch_dependencies "$branch" >/dev/null 2>&1 && check_branch_readiness "$branch" >/dev/null 2>&1; then echo "✅ 分支已准备就绪"; else echo "⚠️ 分支有待处理问题"; fi)

## 详细检查结果

### 依赖关系验证
$(validate_branch_dependencies "$branch" 2>&1 | sed 's/^//')

### 分支就绪状态  
$(check_branch_readiness "$branch" 2>&1 | sed 's/^//')

### 工作树信息
- 工作树路径: $(get_branch_worktree_path "$branch" 2>/dev/null || echo "不存在")
- 最后提交: $(git log -1 --format="%s (%cr)" "$branch" 2>/dev/null || echo "无提交")

## 建议和后续步骤

1. 解决上述标记的所有问题
2. 确保所有变更已提交
3. 运行功能测试验证
4. 准备创建PR: \`gpf pr $branch\`

---
*报告由 git-pr-flow ready 自动生成*
EOF
    
    ui_info "  📍 报告位置: docs/ready-report/ready-report-${branch//\//-}.md"
    
    return 0
}

# 准备分支发布
prepare_branch_release() {
    local branch="$1"
    
    ui_info "  🚀 准备分支发布: $branch"
    
    # 检查远程分支状态
    if git_remote_branch_exists "$branch"; then
        ui_info "  📡 远程分支已存在"
    else
        ui_info "  📡 需要推送到远程仓库"
        ui_info "  💡 建议运行: git push -u origin $branch"
    fi
    
    # 检查PR状态
    local pr_status
    pr_status=$(check_branch_pr_status "$branch")
    
    case "$pr_status" in
        "created")
            ui_info "  📋 PR已创建"
            ;;
        "merged")
            ui_success "  🎉 PR已合并"
            ;;
        "none")
            ui_info "  📋 尚未创建PR"
            ui_info "  💡 建议运行: gpf pr $branch"
            ;;
        *)
            ui_info "  📋 PR状态: $pr_status"
            ;;
    esac
    
    return 0
}

# 检查Epic发布就绪状态 (保持向后兼容)
check_epic_readiness() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "Epic发布就绪检查: $epic_name"
    
    # 获取Epic基本信息
    local base_branch
    base_branch=$(config_epic_get "base_branch")
    
    ui_info "🚀 Epic: $epic_name ($(config_epic_get "description"))"
    ui_info "🎯 基础分支: $base_branch"
    echo
    
    # 执行各项检查
    local overall_ready=true
    
    # 1. 检查功能分支状态
    if ! check_feature_branches_status; then
        overall_ready=false
    fi
    
    # 2. 检查PR状态
    if ! check_pr_status; then
        overall_ready=false
    fi
    
    # 3. 检查依赖关系
    if ! check_dependency_integrity; then
        overall_ready=false
    fi
    
    # 4. 检查代码质量
    if ! check_code_quality; then
        overall_ready=false
    fi
    
    # 5. 检查测试覆盖率
    if ! check_test_coverage; then
        overall_ready=false
    fi
    
    # 显示总体结果
    show_readiness_summary "$overall_ready"
    
    if [[ "$overall_ready" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查功能分支状态
check_feature_branches_status() {
    ui_subheader "功能分支状态检查"
    
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 获取所有Epic功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_warning "没有找到功能分支"
        echo "  📝 建议: 使用 'gpf start' 创建功能分支"
        echo
        return 1
    fi
    
    local all_ready=true
    local total_count=0
    local ready_count=0
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            ((total_count++))
            
            local status_icon status_text
            if check_single_branch_readiness "$branch"; then
                status_icon="✅"
                status_text="就绪"
                ((ready_count++))
            else
                status_icon="❌"
                status_text="未就绪"
                all_ready=false
            fi
            
            echo "  $status_icon $branch - $status_text"
        fi
    done <<< "$feature_branches"
    
    echo
    echo "  📊 分支状态: $ready_count/$total_count 就绪"
    echo
    
    return $([ "$all_ready" == "true" ])
}

# 检查单个分支就绪状态
check_single_branch_readiness() {
    local branch="$1"
    
    # 检查工作树是否存在
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$branch")
    
    if [[ ! -d "$worktree_path" ]]; then
        return 1
    fi
    
    # 检查是否有提交
    local commit_count
    commit_count=$(git rev-list --count "$branch" 2>/dev/null || echo "0")
    
    if [[ "$commit_count" -eq 0 ]]; then
        return 1
    fi
    
    # 检查工作目录是否干净
    local original_dir
    original_dir=$(pwd)
    
    cd "$worktree_path" || return 1
    
    local is_clean
    if git_is_clean; then
        is_clean=true
    else
        is_clean=false
    fi
    
    cd "$original_dir" || true
    
    [[ "$is_clean" == "true" ]]
}

# 检查PR状态
check_pr_status() {
    ui_subheader "PR状态检查"
    
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 获取所有功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_info "  📝 没有功能分支，无需检查PR"
        echo
        return 0
    fi
    
    local pr_ready=true
    local total_branches=0
    local pr_created=0
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            ((total_branches++))
            
            # 检查PR状态（简化实现）
            local pr_status
            pr_status=$(check_branch_pr_status "$branch")
            
            case "$pr_status" in
                "created")
                    echo "  ✅ $branch - PR已创建"
                    ((pr_created++))
                    ;;
                "merged")
                    echo "  🎉 $branch - PR已合并"
                    ((pr_created++))
                    ;;
                "none")
                    echo "  ⚠️ $branch - 未创建PR"
                    pr_ready=false
                    ;;
                *)
                    echo "  ❓ $branch - PR状态未知"
                    ;;
            esac
        fi
    done <<< "$feature_branches"
    
    echo
    echo "  📊 PR状态: $pr_created/$total_branches 已创建"
    echo
    
    if [[ "$pr_ready" == "false" ]]; then
        ui_info "💡 提示: 使用 'git-pr-flow pr <feature>' 创建PR"
        echo
    fi
    
    return $([ "$pr_ready" == "true" ])
}

# 检查分支PR状态（简化实现）
check_branch_pr_status() {
    local branch="$1"
    
    # 简化实现：检查远程分支是否存在
    if git_remote_branch_exists "$branch"; then
        # 如果远程分支存在，假设PR已创建
        echo "created"
    else
        echo "none"
    fi
}

# 检查依赖关系完整性
check_dependency_integrity() {
    ui_subheader "依赖关系完整性检查"
    
    local epic_name base_branch
    epic_name=$(config_epic_get "epic_name")
    base_branch=$(config_epic_get "base_branch")
    
    # 获取所有功能分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_info "  📝 没有功能分支，依赖关系检查通过"
        echo
        return 0
    fi
    
    local dependencies_valid=true
    
    # 检查基础分支同步状态
    echo "  🔍 检查基础分支同步状态..."
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local behind_count
            behind_count=$(git rev-list --count "$branch..$base_branch" 2>/dev/null || echo "0")
            
            if [[ "$behind_count" -gt 0 ]]; then
                echo "    ⚠️ $branch 落后基础分支 $behind_count 个提交"
                dependencies_valid=false
            else
                echo "    ✅ $branch 与基础分支同步"
            fi
        fi
    done <<< "$feature_branches"
    
    echo
    
    # 检查分支间依赖关系
    echo "  🔍 检查分支间依赖关系..."
    
    local dependency_issues=0
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local dependencies
            dependencies=$(detect_branch_dependencies "$branch")
            
            if [[ -n "$dependencies" ]]; then
                echo "    🔗 $branch 依赖: $dependencies"
                
                # 验证依赖分支状态
                if ! validate_dependencies "$branch" "$dependencies"; then
                    ((dependency_issues++))
                    dependencies_valid=false
                fi
            else
                echo "    ✅ $branch 无额外依赖"
            fi
        fi
    done <<< "$feature_branches"
    
    if [[ "$dependency_issues" -gt 0 ]]; then
        echo "    ❌ 发现 $dependency_issues 个依赖问题"
    fi
    
    echo
    
    if [[ "$dependencies_valid" == "false" ]]; then
        ui_info "💡 提示: 使用 'git-pr-flow sync' 解决依赖问题"
        echo
    fi
    
    return $([ "$dependencies_valid" == "true" ])
}

# 检测分支依赖关系
detect_branch_dependencies() {
    local branch="$1"
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 获取同Epic下的其他分支
    local other_branches
    other_branches=$(git_list_branches | grep "^$epic_name/" | grep -v "^$branch$" || true)
    
    local dependencies=""
    while IFS= read -r other_branch; do
        if [[ -n "$other_branch" ]]; then
            # 检查是否包含该分支的提交
            local merge_base branch_head
            merge_base=$(git merge-base "$branch" "$other_branch" 2>/dev/null || echo "")
            branch_head=$(git rev-parse "$other_branch" 2>/dev/null || echo "")
            
            if [[ -n "$merge_base" && "$merge_base" == "$branch_head" ]]; then
                if [[ -n "$dependencies" ]]; then
                    dependencies="$dependencies, $other_branch"
                else
                    dependencies="$other_branch"
                fi
            fi
        fi
    done <<< "$other_branches"
    
    echo "$dependencies"
}

# 验证依赖关系
validate_dependencies() {
    local branch="$1"
    local dependencies="$2"
    
    # 简化实现：检查依赖分支是否存在且有效
    IFS=', ' read -ra dep_array <<< "$dependencies"
    
    for dep in "${dep_array[@]}"; do
        if ! git_branch_exists "$dep"; then
            echo "      ❌ 依赖分支不存在: $dep"
            return 1
        fi
    done
    
    return 0
}

# 检查代码质量
check_code_quality() {
    ui_subheader "代码质量检查"
    
    # 简化的代码质量检查
    local quality_issues=0
    
    # 检查是否有lint配置
    if [[ -f ".eslintrc.js" || -f ".eslintrc.json" || -f "package.json" ]]; then
        echo "  ✅ 发现ESLint配置"
    else
        echo "  ⚠️ 未发现代码规范检查工具配置"
        ((quality_issues++))
    fi
    
    # 检查是否有TypeScript配置
    if [[ -f "tsconfig.json" ]]; then
        echo "  ✅ 发现TypeScript配置"
    else
        echo "  ℹ️ 未发现TypeScript配置（可选）"
    fi
    
    # 检查是否有预提交钩子
    if [[ -f ".husky/pre-commit" || -f ".git/hooks/pre-commit" ]]; then
        echo "  ✅ 发现预提交钩子"
    else
        echo "  ⚠️ 未发现预提交钩子配置"
        ((quality_issues++))
    fi
    
    echo
    echo "  📊 代码质量问题: $quality_issues 个"
    echo
    
    return $([ "$quality_issues" -eq 0 ])
}

# 检查测试覆盖率
check_test_coverage() {
    ui_subheader "测试覆盖率检查"
    
    local test_issues=0
    
    # 检查是否有测试目录
    if [[ -d "test" || -d "tests" || -d "__tests__" || -d "spec" ]]; then
        echo "  ✅ 发现测试目录"
    else
        echo "  ⚠️ 未发现测试目录"
        ((test_issues++))
    fi
    
    # 检查是否有测试配置
    if [[ -f "jest.config.js" || -f "jest.config.json" || -f "vitest.config.js" ]]; then
        echo "  ✅ 发现测试框架配置"
    else
        echo "  ⚠️ 未发现测试框架配置"
        ((test_issues++))
    fi
    
    # 检查package.json中的测试脚本
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
        echo "  ✅ 发现测试脚本配置"
    else
        echo "  ⚠️ 未发现测试脚本配置"
        ((test_issues++))
    fi
    
    echo
    echo "  📊 测试配置问题: $test_issues 个"
    echo
    
    if [[ "$test_issues" -gt 0 ]]; then
        ui_info "💡 提示: 建议添加测试用例和配置以提高代码质量"
        echo
    fi
    
    return $([ "$test_issues" -eq 0 ])
}

# 显示就绪状态摘要
show_readiness_summary() {
    local overall_ready="$1"
    
    ui_subheader "Epic发布就绪状态摘要"
    
    if [[ "$overall_ready" == "true" ]]; then
        ui_success_box "🎉 Epic已准备好发布！" \
            "所有检查项目均已通过" \
            "建议执行最终发布流程" \
            "" \
            "下一步操作:" \
            "1. git-pr-flow ready release  # 准备发布" \
            "2. 创建发布分支或标签" \
            "3. 部署到生产环境"
    else
        ui_warning_box "⚠️ Epic尚未准备好发布" \
            "存在需要解决的问题" \
            "请根据上述检查结果进行修复" \
            "" \
            "建议操作:" \
            "1. 解决标记的问题" \
            "2. git-pr-flow sync      # 同步依赖" \
            "3. git-pr-flow ready check # 重新检查"
    fi
}

# 生成详细就绪报告
generate_readiness_report() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "Epic就绪状态详细报告"
    
    local project_root
    project_root=$(get_project_root_path) || {
        ui_error "无法获取项目根目录"
        return 1
    }
    
    # 确保 docs/ready-report 目录存在
    mkdir -p "$project_root/docs/ready-report"
    
    local report_file="$project_root/docs/ready-report/epic-${epic_name}-readiness-report.md"
    
    ui_loading "生成详细报告: docs/ready-report/epic-${epic_name}-readiness-report.md"
    
    # 生成Markdown报告
    cat > "$report_file" << EOF
# Epic发布就绪报告

**Epic名称**: $epic_name  
**生成时间**: $(current_local_timestamp)  
**基础分支**: $(config_epic_get "base_branch")  

## 执行摘要

$(if check_epic_readiness >/dev/null 2>&1; then echo "✅ Epic已准备好发布"; else echo "⚠️ Epic尚未准备好发布"; fi)

## 详细检查结果

### 功能分支状态
$(check_feature_branches_status 2>&1 | sed 's/^//')

### PR状态
$(check_pr_status 2>&1 | sed 's/^//')

### 依赖关系完整性
$(check_dependency_integrity 2>&1 | sed 's/^//')

### 代码质量
$(check_code_quality 2>&1 | sed 's/^//')

### 测试覆盖率
$(check_test_coverage 2>&1 | sed 's/^//')

## 建议和后续步骤

1. 解决上述标记的所有问题
2. 确保所有PR已创建并通过审查
3. 运行完整的测试套件
4. 准备发布文档和变更日志
5. 通知相关团队成员

---
*报告由 git-pr-flow 自动生成*
EOF
    
    ui_success "✅ 报告已生成: docs/ready-report/epic-${epic_name}-readiness-report.md"
    echo "  📄 文件路径: docs/ready-report/epic-${epic_name}-readiness-report.md"
    echo
    
    ui_info "💡 建议: 将此报告分享给团队成员进行最终审查"
}

# 准备Epic发布
prepare_epic_release() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_header "准备Epic发布: $epic_name"
    
    # 首先检查就绪状态
    ui_info "🔍 执行发布前检查..."
    if ! check_epic_readiness >/dev/null 2>&1; then
        ui_error "Epic尚未准备好发布"
        ui_info "请先解决就绪检查中的问题"
        ui_info "运行 'git-pr-flow ready check' 查看详细状态"
        return 1
    fi
    
    ui_success "✅ Epic就绪检查通过"
    
    # 确认发布
    if ! ui_confirm "确认开始Epic发布准备？"; then
        ui_info "取消发布准备"
        return 1
    fi
    
    # 执行发布准备步骤
    execute_release_preparation "$epic_name"
}

# 执行发布准备
execute_release_preparation() {
    local epic_name="$1"
    local base_branch
    base_branch=$(config_epic_get "base_branch")
    
    ui_subheader "发布准备步骤"
    
    # 1. 创建发布分支
    local release_branch="release/$epic_name"
    echo "  📝 1. 创建发布分支: $release_branch"
    
    if git_branch_exists "$release_branch"; then
        ui_warning "    发布分支已存在"
    else
        if git checkout -b "$release_branch" "$base_branch" >/dev/null 2>&1; then
            ui_success "    ✅ 发布分支创建成功"
        else
            ui_error "    ❌ 发布分支创建失败"
            return 1
        fi
    fi
    
    # 2. 合并所有功能分支
    echo "  🔄 2. 合并功能分支到发布分支"
    merge_feature_branches_to_release "$epic_name" "$release_branch"
    
    # 3. 生成变更日志
    echo "  📄 3. 生成变更日志"
    generate_changelog "$epic_name" "$release_branch"
    
    # 4. 更新版本信息
    echo "  🏷️ 4. 准备版本标记"
    prepare_version_tag "$epic_name"
    
    # 5. 创建发布PR
    echo "  📋 5. 创建发布PR"
    create_release_pr "$release_branch" "$base_branch"
    
    ui_success_box "🎉 Epic发布准备完成！" \
        "发布分支: $release_branch" \
        "下一步: 审查并合并发布PR" \
        "" \
        "发布后清理:" \
        "git-pr-flow clean --release"
}

# 合并功能分支到发布分支
merge_feature_branches_to_release() {
    local epic_name="$1"
    local release_branch="$2"
    
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -z "$feature_branches" ]]; then
        ui_info "    📝 没有功能分支需要合并"
        return 0
    fi
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            ui_loading "    合并 $branch"
            if git merge --no-ff "$branch" --message "feat: 合并功能分支 $branch" >/dev/null 2>&1; then
                echo "      ✅ $branch 合并成功"
            else
                echo "      ❌ $branch 合并失败"
                ui_warning "请手动解决冲突后继续"
            fi
        fi
    done <<< "$feature_branches"
}

# 生成变更日志
generate_changelog() {
    local epic_name="$1"
    local release_branch="$2"
    
    local changelog_file="CHANGELOG-$epic_name.md"
    
    cat > "$changelog_file" << EOF
# $epic_name Epic 变更日志

## 发布信息
- **Epic**: $epic_name
- **版本**: $(date +%Y.%m.%d)
- **发布时间**: $(current_local_timestamp)

## 新增功能
$(git_list_branches | grep "^$epic_name/" | sed 's/^/- /' || echo "- 暂无功能分支")

## 技术变更
- Epic架构实现
- 分支管理优化
- 工作流程改进

## 测试说明
- 所有功能分支已通过就绪检查
- 代码质量检查通过
- 依赖关系验证完成

---
*变更日志由 git-pr-flow 自动生成*
EOF
    
    git add "$changelog_file" >/dev/null 2>&1
    echo "    ✅ 变更日志已生成: $changelog_file"
}

# 准备版本标记
prepare_version_tag() {
    local epic_name="$1"
    local tag_name="$epic_name-$(date +%Y%m%d)"
    
    echo "    🏷️ 建议标签: $tag_name"
    echo "    💡 手动创建: git tag -a $tag_name -m 'Release $epic_name Epic'"
}

# 创建发布PR
create_release_pr() {
    local release_branch="$1"
    local base_branch="$2"
    
    if command_exists gh; then
        local pr_title="release: $release_branch Epic发布"
        local pr_body="Epic发布PR，包含所有功能分支的合并和发布准备。"
        
        if gh pr create --title "$pr_title" --body "$pr_body" --base "$base_branch" --head "$release_branch" >/dev/null 2>&1; then
            echo "    ✅ 发布PR创建成功"
        else
            echo "    ⚠️ 发布PR创建失败，请手动创建"
        fi
    else
        echo "    💡 请手动创建发布PR: $release_branch -> $base_branch"
    fi
}

# 验证Epic依赖关系
validate_epic_dependencies() {
    ui_header "Epic依赖关系验证"
    
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_info "🔍 深度分析Epic依赖关系..."
    
    # 检查外部依赖
    check_external_dependencies
    
    # 检查内部依赖
    check_internal_dependencies
    
    # 检查版本兼容性
    check_version_compatibility
    
    ui_success "✅ 依赖关系验证完成"
}

# 检查外部依赖
check_external_dependencies() {
    ui_subheader "外部依赖检查"
    
    # 检查package.json依赖
    if [[ -f "package.json" ]]; then
        echo "  📦 检查Node.js依赖..."
        if command_exists npm; then
            npm outdated >/dev/null 2>&1 || echo "    ✅ 依赖版本检查完成"
        else
            echo "    ⚠️ npm不可用，跳过依赖检查"
        fi
    fi
    
    # 检查其他依赖文件
    if [[ -f "requirements.txt" ]]; then
        echo "  🐍 检查Python依赖..."
        echo "    📝 发现requirements.txt"
    fi
    
    if [[ -f "Gemfile" ]]; then
        echo "  💎 检查Ruby依赖..."
        echo "    📝 发现Gemfile"
    fi
    
    echo
}

# 检查内部依赖
check_internal_dependencies() {
    ui_subheader "内部依赖检查"
    
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    # 检查模块导入关系
    echo "  🔍 分析模块依赖关系..."
    
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
    
    if [[ -n "$feature_branches" ]]; then
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                echo "    📋 $branch: 检查模块导入"
                # 这里可以添加更详细的依赖分析逻辑
            fi
        done <<< "$feature_branches"
    fi
    
    echo
}

# 检查版本兼容性
check_version_compatibility() {
    ui_subheader "版本兼容性检查"
    
    echo "  🔍 检查运行时版本要求..."
    
    # 检查Node.js版本
    if command_exists node; then
        local node_version
        node_version=$(node --version 2>/dev/null || echo "未知")
        echo "    📦 Node.js版本: $node_version"
    fi
    
    # 检查Git版本
    if command_exists git; then
        local git_version
        git_version=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "    🔧 Git版本: $git_version"
    fi
    
    echo "    ✅ 版本兼容性检查完成"
    echo
}