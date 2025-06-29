#!/usr/bin/env bash

# Git PR Flow - status命令实现
# Epic进度仪表盘，显示整体状态、分支关系、工作树状态等

# 引入环境检测工具
COMMAND_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$COMMAND_SCRIPT_DIR/../utils/environment.sh"

# 引入路径管理工具
source "$(dirname "${BASH_SOURCE[0]}")/../utils/paths.sh"

# status命令主函数
cmd_status() {
    local target_epic_or_scope="${1:-}"
    
    # 如果没有参数，显示全局概览
    if [[ -z "$target_epic_or_scope" ]]; then
        show_all_epics_overview
        return 0
    fi
    
    # 检查是否是内置作用域
    case "$target_epic_or_scope" in
        "global")
            show_global_status_dashboard
            ;;
        "worktrees")
            show_worktrees_status
            ;;
        "branches")
            show_branches_status
            ;;
        *)
            # 尝试作为epic名称处理
            show_specific_epic_status "$target_epic_or_scope"
            ;;
    esac
}

# Epic状态仪表盘
show_epic_status_dashboard() {
    local epic_name="$1"
    ui_header "Epic进度仪表盘: $epic_name"
    
    # 检查Epic配置
    if ! config_epic_exists "$epic_name"; then
        ui_warning "未找到Epic配置: $epic_name"
        ui_info "请先运行: gpf init $epic_name"
        echo
        show_repository_basic_status
        return 0
    fi
    
    if ! config_epic_validate "$epic_name"; then
        ui_error "Epic配置文件损坏: $epic_name"
        return 1
    fi
    
    # 基本Epic信息
    show_epic_basic_info "$epic_name"
    
    # 分支架构图
    show_epic_branch_architecture "$epic_name"
    
    # 工作树状态
    show_epic_worktrees_status
    
    # Epic进度统计
    show_epic_progress_summary
    
    # 快速操作提示
    show_epic_quick_actions
}

# 显示Epic基本信息
show_epic_basic_info() {
    local target_epic="$1"
    local epic_name description base_branch created_at
    epic_name=$(config_epic_get "epic_name" "$target_epic")
    description=$(config_epic_get "description" "$target_epic")
    base_branch=$(config_epic_get "base_branch" "$target_epic")
    created_at=$(config_epic_get "created_at" "$target_epic")
    
    ui_subheader "Epic基本信息"
    echo "  🚀 Epic名称: $epic_name"
    echo "  📝 描述: $description"
    echo "  🌿 基础分支: $base_branch"
    echo "  📅 创建时间: $created_at"
    
    # 自动化设置状态
    local auto_switch auto_sync auto_cleanup
    auto_switch=$(config_epic_get "auto_switch_branch" "$target_epic")
    auto_sync=$(config_epic_get "auto_sync" "$target_epic")
    auto_cleanup=$(config_epic_get "auto_cleanup" "$target_epic")
    
    echo "  🔄 自动分支切换: $(format_bool_status "$auto_switch")"
    echo "  🔄 自动同步: $(format_bool_status "$auto_sync")"
    echo "  🧹 自动清理: $(format_bool_status "$auto_cleanup")"
    echo
}

# 显示Epic分支架构
show_epic_branch_architecture() {
    local target_epic="$1"
    local epic_name base_branch
    epic_name=$(config_epic_get "epic_name" "$target_epic")
    base_branch=$(config_epic_get "base_branch" "$target_epic")
    
    ui_subheader "分支架构"
    
    # 获取所有Epic相关分支
    local feature_branches
    feature_branches=$(git_list_branches | grep "^$epic_name/" | sort || true)
    
    if [[ -z "$feature_branches" ]]; then
        echo "  🌿 $base_branch (基础分支)"
        echo "    └── 暂无子功能分支"
        echo
        return 0
    fi
    
    echo "  🌿 $base_branch (基础分支)"
    
    # 构建分支依赖树
    local branches_array=()
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            branches_array+=("$branch")
        fi
    done <<< "$feature_branches"
    
    for i in "${!branches_array[@]}"; do
        local branch="${branches_array[$i]}"
        local status_info worktree_path commits_count
        
        worktree_path=$(branch_to_worktree_path "$branch")
        commits_count=$(git rev-list --count "$branch" 2>/dev/null || echo "0")
        
        # 确定状态图标
        local status_icon
        if [[ -d "$worktree_path" ]]; then
            status_icon="🏠"
            status_info="活跃工作树"
        else
            status_icon="📋"
            status_info="仅分支"
        fi
        
        # 确定树形连接符
        local tree_symbol
        if [[ $i -eq $((${#branches_array[@]} - 1)) ]]; then
            tree_symbol="└──"
        else
            tree_symbol="├──"
        fi
        
        echo "    $tree_symbol $status_icon $branch ($commits_count 提交, $status_info)"
        
        # 显示工作树路径
        if [[ -d "$worktree_path" ]]; then
            local next_prefix
            if [[ $i -eq $((${#branches_array[@]} - 1)) ]]; then
                next_prefix="        "
            else
                next_prefix="    │   "
            fi
            echo "${next_prefix}└─ 工作树: $worktree_path"
        fi
    done
    echo
}

# 显示Epic工作树状态
show_epic_worktrees_status() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_subheader "工作树状态"
    
    # 获取所有相关工作树
    local epic_worktrees=()
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    local has_epic_worktrees=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local current_worktree_path="${BASH_REMATCH[1]}"
            local branch_name
            branch_name=$(git_worktree_branch "$current_worktree_path")
            
            if [[ "$branch_name" =~ ^$epic_name/ ]]; then
                has_epic_worktrees=true
                show_worktree_detailed_status "$current_worktree_path" "$branch_name"
            fi
        fi
    done <<< "$worktree_info"
    
    if [[ "$has_epic_worktrees" == "false" ]]; then
        echo "  📝 当前没有活跃的工作树"
        echo "  💡 使用 'gpf start $epic_name/feature-name' 创建新的功能开发环境"
    fi
    echo
}

# 显示工作树详细状态
show_worktree_detailed_status() {
    local worktree_path="$1"
    local branch_name="$2"
    
    # 获取工作树状态
    local status_summary
    if [[ -d "$worktree_path" ]]; then
        cd "$worktree_path" || return 1
        local modified staged untracked
        modified=$(git diff --name-only | wc -l | tr -d ' ')
        staged=$(git diff --cached --name-only | wc -l | tr -d ' ')
        untracked=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')
        
        if [[ "$modified" == "0" && "$staged" == "0" && "$untracked" == "0" ]]; then
            status_summary="✅ 干净"
        else
            status_summary="⚠️ 修改:$modified 暂存:$staged 未跟踪:$untracked"
        fi
        cd - >/dev/null || true
    else
        status_summary="❌ 路径不存在"
    fi
    
    echo "  🏠 $branch_name"
    echo "    ├─ 路径: $worktree_path"
    echo "    └─ 状态: $status_summary"
}

# 显示Epic进度统计
show_epic_progress_summary() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_subheader "进度统计"
    
    # 统计分支数量
    local total_branches active_worktrees
    total_branches=$(git_list_branches | grep "^$epic_name/" | wc -l | tr -d ' ')
    
    # 统计活跃工作树
    active_worktrees=0
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local current_worktree_path="${BASH_REMATCH[1]}"
            local branch_name
            branch_name=$(git_worktree_branch "$current_worktree_path")
            
            if [[ "$branch_name" =~ ^$epic_name/ ]]; then
                ((active_worktrees++))
            fi
        fi
    done <<< "$worktree_info"
    
    # 计算提交统计
    local total_commits=0
    if [[ "$total_branches" -gt 0 ]]; then
        local feature_branches
        feature_branches=$(git_list_branches | grep "^$epic_name/" || true)
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                local commits
                commits=$(git rev-list --count "$branch" 2>/dev/null || echo "0")
                total_commits=$((total_commits + commits))
            fi
        done <<< "$feature_branches"
    fi
    
    echo "  📊 分支总数: $total_branches"
    echo "  🏠 活跃工作树: $active_worktrees"
    echo "  📝 总提交数: $total_commits"
    
    # 进度百分比（简单实现：活跃工作树/总分支）
    local progress_percentage=0
    if [[ "$total_branches" -gt 0 ]]; then
        progress_percentage=$((active_worktrees * 100 / total_branches))
    fi
    echo "  📈 开发进度: ${progress_percentage}% (${active_worktrees}/${total_branches} 功能正在开发)"
    echo
}

# 显示快速操作提示
show_epic_quick_actions() {
    local epic_name
    epic_name=$(config_epic_get "epic_name")
    
    ui_subheader "快速操作"
    echo "  🚀 开始新功能: gpf start $epic_name/feature-name"
    echo "  🔄 同步依赖关系: git-pr-flow sync"
    echo "  📋 创建PR: git-pr-flow pr $epic_name/feature-name"
    echo "  💻 VS Code集成: git-pr-flow code $epic_name/feature-name"
    echo "  🧹 清理环境: git-pr-flow clean"
    echo
}

# 全局状态仪表盘
show_global_status_dashboard() {
    ui_header "全局状态仪表盘"
    
    # 仓库基本信息
    show_repository_basic_status
    
    # 所有工作树状态
    show_all_worktrees_status
    
    # 所有Epic概览
    show_all_epics_overview
}

# 显示仓库基本状态
show_repository_basic_status() {
    ui_subheader "仓库状态"
    
    local current_branch repo_root
    current_branch=$(git_current_branch)
    repo_root=$(git rev-parse --show-toplevel)
    
    echo "  📁 仓库路径: $repo_root"
    echo "  🌿 当前分支: $current_branch"
    
    # 检查工作目录状态
    local status_summary
    if git_is_clean; then
        status_summary="✅ 干净"
    else
        status_summary="⚠️ $(git_status_summary)"
    fi
    echo "  📊 工作目录: $status_summary"
    
    # 统计总体分支数量
    local total_branches epic_branches
    total_branches=$(git_list_branches | wc -l | tr -d ' ')
    epic_branches=$(git_list_epic_branches | wc -l | tr -d ' ')
    
    echo "  🌿 总分支数: $total_branches"
    echo "  🚀 Epic分支数: $epic_branches"
    echo
}

# 显示所有工作树状态
show_all_worktrees_status() {
    ui_subheader "所有工作树"
    
    local worktree_info
    worktree_info=$(git_list_worktrees)
    
    local worktree_count=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.+)$ ]]; then
            local current_worktree_path="${BASH_REMATCH[1]}"
            local branch_name
            branch_name=$(git_worktree_branch "$current_worktree_path")
            
            ((worktree_count++))
            echo "  🏠 $current_worktree_path"
            echo "    └─ 分支: $branch_name"
        fi
    done <<< "$worktree_info"
    
    if [[ "$worktree_count" -eq 0 ]]; then
        echo "  📝 当前没有工作树"
    fi
    echo
}

# 显示所有Epic概览
show_all_epics_overview() {
    ui_subheader "Epic概览"
    
    # 这是一个简化实现，在实际项目中可能需要更复杂的Epic检测逻辑
    local epic_branches
    epic_branches=$(git_list_epic_branches)
    
    if [[ -z "$epic_branches" ]]; then
        echo "  📝 当前没有Epic分支"
        echo "  💡 使用 'gpf init <epic-name>' 开始第一个Epic"
        echo
        return 0
    fi
    
    # 分组显示Epic
    local current_epic=""
    local epic_list=()
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local epic_part="${branch%%/*}"
            if [[ "$epic_part" != "$current_epic" ]]; then
                current_epic="$epic_part"
                epic_list+=("$epic_part")
            fi
        fi
    done <<< "$epic_branches"
    
    for epic in "${epic_list[@]}"; do
        local epic_branch_count
        epic_branch_count=$(git_list_branches | grep "^$epic/" | wc -l | tr -d ' ')
        echo "  🚀 $epic ($epic_branch_count 个子功能)"
    done
    echo
}

# 工作树详细状态
show_worktrees_status() {
    ui_header "工作树详细状态"
    show_all_worktrees_status
}

# 分支详细状态
show_branches_status() {
    ui_header "分支详细状态"
    
    ui_subheader "所有分支"
    local all_branches
    all_branches=$(git_list_branches)
    
    while IFS= read -r branch; do
        if [[ -n "$branch" ]]; then
            local commits_count is_epic_branch
            commits_count=$(git rev-list --count "$branch" 2>/dev/null || echo "0")
            
            if [[ "$branch" =~ / ]]; then
                is_epic_branch="🚀"
            else
                is_epic_branch="🌿"
            fi
            
            echo "  $is_epic_branch $branch ($commits_count 提交)"
        fi
    done <<< "$all_branches"
    echo
}

# 辅助函数：格式化布尔状态
format_bool_status() {
    local value="$1"
    case "$value" in
        "true"|"True"|"TRUE"|"1")
            echo "✅ 启用"
            ;;
        *)
            echo "❌ 禁用"
            ;;
    esac
}

# 显示所有Epic概览
show_all_epics_overview() {
    ui_header "Git PR Flow 项目概览"
    
    # 显示项目基本信息
    show_repository_basic_status
    
    # 列出所有Epic
    show_all_epics_list
    
    # 显示工作树概览
    ui_subheader "工作树概览"
    show_worktrees_summary
    
    echo
    ui_info "💡 使用 'gpf status <epic-name>' 查看特定Epic的详细状态"
    ui_info "💡 使用 'gpf status global' 查看全局详细状态"
}

# 显示特定Epic状态
show_specific_epic_status() {
    local epic_name="$1"
    
    # 检查Epic是否存在
    if ! config_epic_exists "$epic_name"; then
        ui_error "Epic '$epic_name' 不存在"
        ui_info "可用的Epic:"
        show_all_epics_list
        return 1
    fi
    
    # 显示Epic详细状态
    show_epic_status_dashboard "$epic_name"
}

# 工作树概览
show_worktrees_summary() {
    local worktree_count=0
    
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/*/; do
            if [[ -d "$worktree" ]]; then
                local worktree_name
                worktree_name=$(basename "$worktree")
                echo "  📁 $worktree_name"
                ((worktree_count++))
            fi
        done
    fi
    
    if [[ $worktree_count -eq 0 ]]; then
        echo "  💭 暂无工作树"
    else
        echo "  📊 总计: $worktree_count 个工作树"
    fi
}

# 显示所有Epic列表
show_all_epics_list() {
    ui_subheader "Epic状态概览"
    
    local epic_count=0
    local has_epics=false
    
    # 检查所有epic分支
    local epic_branches
    epic_branches=$(git branch -a | grep -E "epic/" | sed 's/^[* ] //' | sed 's/^remotes\/[^/]*\///' | sort -u || true)
    
    if [[ -n "$epic_branches" ]]; then
        has_epics=true
        while IFS= read -r branch; do
            if [[ -n "$branch" ]]; then
                local epic_name="${branch#epic/}"
                local status_icon config_status worktree_status
                
                # 检查配置文件状态（使用新的路径API）
                if epic_config_exists "$epic_name"; then
                    config_status="✅"
                else
                    config_status="❌"
                fi
                
                # 检查工作树状态（使用新的路径API）
                if epic_worktree_exists "$epic_name"; then
                    worktree_status="🏠"
                else
                    worktree_status="📋"
                fi
                
                # 获取子功能数量
                local feature_count
                feature_count=$(git branch | grep -c "^[* ] $epic_name/" 2>/dev/null || echo "0")
                
                echo "  $config_status $worktree_status $branch ($feature_count 个子功能)"
                ((epic_count++))
            fi
        done <<< "$epic_branches"
    fi
    
    # 检查工作树目录中的孤立epic（有目录但无分支）
    if [[ -d ".worktrees" ]]; then
        for worktree in .worktrees/epic--*/; do
            if [[ -d "$worktree" ]]; then
                local worktree_name
                worktree_name=$(basename "$worktree")
                local epic_name="${worktree_name#epic--}"
                local branch_name="epic/$epic_name"
                
                # 检查是否有对应的分支
                if ! git branch | grep -q "^[* ] $branch_name$"; then
                    echo "  ⚠️  💼 $worktree_name (孤立工作树，无对应分支)"
                    has_epics=true
                    ((epic_count++))
                fi
            fi
        done
    fi
    
    if [[ "$has_epics" == "false" ]]; then
        echo "  💭 暂无Epic"
        echo "  💡 使用 'gpf init <epic-name>' 创建新Epic"
    else
        echo "  📊 总计: $epic_count 个Epic"
        echo
        echo "  图例: ✅=有配置 ❌=缺配置 🏠=有工作树 📋=仅分支 ⚠️=异常"
    fi
}