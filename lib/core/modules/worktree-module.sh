#!/bin/bash
# GPF 工作树管理模块 - 提供智能工作树切换和生命周期管理
# 本模块为start/clean/sync命令提供完整的worktree管理服务

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/worktree-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/git-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/environment-composite.sh"

# ==============================================================================
# 智能工作树管理模块
# ==============================================================================

# 智能切换到工作树（start命令核心方法）
worktree_module_intelligent_switch() {
    local target_input="$1"
    local operation_mode="${2:-auto}"     # auto/create/switch
    local base_branch="${3:-}"            # 仅创建时需要
    local force_type="${4:-}"             # epic/feature (可选强制类型)
    
    # 解析目标输入
    local parse_result
    parse_result=$(worktree_module_parse_target "$target_input" "$force_type") || return 1
    
    local target_type="${parse_result%%:*}"
    local clean_name="${parse_result#*:}"
    local target_branch
    
    # 生成目标分支名
    case "$target_type" in
        "epic")
            target_branch="epic-$clean_name-e"
            ;;
        "feature")
            # Feature需要Epic环境
            local current_epic
            current_epic=$(worktree_module_extract_current_epic) || {
                echo "❌ 错误：创建Feature需要Epic环境" >&2
                return 1
            }
            target_branch="epic-$current_epic-e-$clean_name-ef"
            ;;
        *)
            echo "❌ 错误：未知的目标类型: $target_type" >&2
            return 1
            ;;
    esac
    
    # 检查工作树是否存在
    local worktree_path="$PROJECT_ROOT/.worktrees/$target_branch"
    
    if [[ -d "$worktree_path" ]]; then
        # 工作树存在，直接切换
        case "$operation_mode" in
            "auto"|"switch")
                worktree_module_switch_to_worktree "$target_branch" || return 1
                echo "✅ 已切换到现有工作树: $target_branch"
                ;;
            "create")
                echo "⚠️ 工作树已存在，切换到现有环境: $target_branch"
                worktree_module_switch_to_worktree "$target_branch" || return 1
                ;;
        esac
    else
        # 工作树不存在，需要创建
        case "$operation_mode" in
            "auto"|"create")
                worktree_module_create_and_switch "$target_branch" "$base_branch" || return 1
                echo "🚀 已创建并切换到新工作树: $target_branch"
                ;;
            "switch")
                echo "❌ 错误：工作树不存在: $target_branch" >&2
                return 1
                ;;
        esac
    fi
    
    # 返回切换结果
    cat <<EOF
{
    "success": true,
    "target_branch": "$target_branch",
    "worktree_path": "$worktree_path",
    "operation": "$([[ -d "$worktree_path" ]] && echo "switch" || echo "create")"
}
EOF
}

# 工作树生命周期管理（clean命令使用）
worktree_module_lifecycle_management() {
    local action="$1"                    # list/analyze/cleanup/remove
    local target_pattern="${2:-}"        # 可选的目标模式
    local safety_level="${3:-safe}"      # safe/warning/force
    
    case "$action" in
        "list")
            worktree_module_list_worktrees "$target_pattern"
            ;;
        "analyze")
            worktree_module_analyze_worktrees "$target_pattern"
            ;;
        "cleanup")
            worktree_module_cleanup_worktrees "$target_pattern" "$safety_level"
            ;;
        "remove")
            worktree_module_remove_worktree "$target_pattern" "$safety_level"
            ;;
        *)
            echo "❌ 错误：未知的生命周期管理动作: $action" >&2
            return 1
            ;;
    esac
}

# 工作树状态监控（status命令使用）
worktree_module_status_monitoring() {
    local monitoring_scope="${1:-all}"    # all/epic/feature/current
    local detail_level="${2:-summary}"    # summary/detailed/full
    
    # 获取工作树列表
    local worktree_list
    worktree_list=$(worktree_module_get_worktree_list "$monitoring_scope") || return 1
    
    local results="[]"
    
    # 遍历工作树
    while IFS= read -r worktree_info; do
        [[ -n "$worktree_info" ]] || continue
        
        local worktree_path="${worktree_info%% *}"
        local branch_name="${worktree_info##* }"
        
        local status_info
        status_info=$(worktree_module_get_worktree_status "$worktree_path" "$branch_name" "$detail_level") || continue
        
        results=$(echo "$results" | jq --argjson status "$status_info" '. += [$status]')
    done <<< "$worktree_list"
    
    # 返回监控结果
    cat <<EOF
{
    "monitoring_scope": "$monitoring_scope",
    "detail_level": "$detail_level",
    "worktrees": $results
}
EOF
}

# ==============================================================================
# 工作树解析和验证
# ==============================================================================

# 解析目标输入
worktree_module_parse_target() {
    local target_input="$1"
    local force_type="${2:-}"
    
    # 清理输入
    local clean_input
    clean_input=$(strip_epic_prefix_from_input "$target_input")
    clean_input=$(strip_suffix_from_input "$clean_input")
    
    # 验证名称格式
    if ! validate_name_format "$clean_input"; then
        echo "❌ 错误：名称格式不正确: $clean_input" >&2
        return 1
    fi
    
    # 确定目标类型
    local target_type
    if [[ -n "$force_type" ]]; then
        target_type="$force_type"
    else
        # 自动推断类型
        if [[ "$target_input" =~ -ef$ ]]; then
            target_type="feature"
        elif [[ "$target_input" =~ -e$ ]]; then
            target_type="epic"
        else
            # 根据当前环境和名称特征判断
            local current_env
            current_env=$(environment_detect_complete 2>/dev/null || echo "unknown")
            
            if [[ "$current_env" == "epic" && "$clean_input" =~ - ]]; then
                target_type="feature"
            else
                target_type="epic"
            fi
        fi
    fi
    
    echo "$target_type:$clean_input"
}

# 提取当前Epic名称
worktree_module_extract_current_epic() {
    local current_env
    current_env=$(environment_detect_complete) || return 1
    
    if [[ "$current_env" == "epic" ]]; then
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
        extract_epic_from_branch "$current_branch"
    elif [[ "$current_env" == "feature" ]]; then
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
        extract_epic_from_branch "$current_branch"
    else
        echo "❌ 错误：当前不在Epic或Feature环境中" >&2
        return 1
    fi
}

# ==============================================================================
# 工作树基础操作
# ==============================================================================

# 切换到指定工作树
worktree_module_switch_to_worktree() {
    local target_branch="$1"
    local worktree_path="$PROJECT_ROOT/.worktrees/$target_branch"
    
    # 验证工作树存在
    [[ -d "$worktree_path" ]] || {
        echo "❌ 错误：工作树不存在: $worktree_path" >&2
        return 1
    }
    
    # 切换目录
    cd "$worktree_path" || {
        echo "❌ 错误：无法切换到工作树目录" >&2
        return 1
    }
    
    # 切换分支（如果需要）
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
        echo "❌ 错误：无法获取当前分支" >&2
        return 1
    }
    
    if [[ "$current_branch" != "$target_branch" ]]; then
        git checkout "$target_branch" >/dev/null 2>&1 || {
            echo "❌ 错误：无法切换到分支: $target_branch" >&2
            return 1
        }
    fi
    
    return 0
}

# 创建并切换到新工作树
worktree_module_create_and_switch() {
    local target_branch="$1"
    local base_branch="${2:-develop}"
    local worktree_path="$PROJECT_ROOT/.worktrees/$target_branch"
    
    # 确保基础分支存在且是最新的
    if ! worktree_module_prepare_base_branch "$base_branch"; then
        echo "❌ 错误：基础分支准备失败: $base_branch" >&2
        return 1
    fi
    
    # 创建工作树
    if ! git worktree add "$worktree_path" -b "$target_branch" "$base_branch"; then
        echo "❌ 错误：工作树创建失败" >&2
        return 1
    fi
    
    # 切换到新工作树
    worktree_module_switch_to_worktree "$target_branch" || {
        # 创建失败，清理工作树
        git worktree remove "$worktree_path" --force 2>/dev/null || true
        return 1
    }
    
    return 0
}

# 准备基础分支
worktree_module_prepare_base_branch() {
    local base_branch="$1"
    
    # 切换到项目根目录
    local original_dir=$(pwd)
    cd "$PROJECT_ROOT" || return 1
    
    # 确保在正确的分支上
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
        cd "$original_dir"
        return 1
    }
    
    if [[ "$current_branch" != "$base_branch" ]]; then
        git checkout "$base_branch" >/dev/null 2>&1 || {
            cd "$original_dir"
            echo "❌ 错误：无法切换到基础分支: $base_branch" >&2
            return 1
        }
    fi
    
    # 更新基础分支
    git pull origin "$base_branch" >/dev/null 2>&1 || {
        cd "$original_dir"
        echo "⚠️ 警告：无法更新基础分支，使用本地版本" >&2
    }
    
    cd "$original_dir"
    return 0
}

# ==============================================================================
# 工作树列表和分析
# ==============================================================================

# 获取工作树列表
worktree_module_get_worktree_list() {
    local scope="${1:-all}"
    
    local worktree_base="$PROJECT_ROOT/.worktrees"
    [[ -d "$worktree_base" ]] || return 0
    
    case "$scope" in
        "all")
            find "$worktree_base" -maxdepth 1 -type d -name "epic-*" | while read -r dir; do
                local branch_name=$(basename "$dir")
                echo "$dir $branch_name"
            done
            ;;
        "epic")
            find "$worktree_base" -maxdepth 1 -type d -name "epic-*-e" | while read -r dir; do
                local branch_name=$(basename "$dir")
                echo "$dir $branch_name"
            done
            ;;
        "feature")
            find "$worktree_base" -maxdepth 1 -type d -name "epic-*-ef" | while read -r dir; do
                local branch_name=$(basename "$dir")
                echo "$dir $branch_name"
            done
            ;;
        "current")
            local current_env
            current_env=$(environment_detect_complete 2>/dev/null) || return 1
            
            if [[ "$current_env" =~ ^(epic|feature)$ ]]; then
                local current_path=$(pwd)
                local branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
                echo "$current_path $branch_name"
            fi
            ;;
        *)
            echo "❌ 错误：未知的工作树范围: $scope" >&2
            return 1
            ;;
    esac
}

# 列出工作树
worktree_module_list_worktrees() {
    local pattern="${1:-}"
    
    local worktree_list
    worktree_list=$(worktree_module_get_worktree_list "all") || return 1
    
    local results="[]"
    
    while IFS= read -r worktree_info; do
        [[ -n "$worktree_info" ]] || continue
        
        local worktree_path="${worktree_info%% *}"
        local branch_name="${worktree_info##* }"
        
        # 应用模式过滤
        if [[ -n "$pattern" && ! "$branch_name" =~ $pattern ]]; then
            continue
        fi
        
        # 获取基础信息
        local branch_type="unknown"
        if [[ "$branch_name" =~ ^epic-.*-e$ ]]; then
            branch_type="epic"
        elif [[ "$branch_name" =~ ^epic-.*-e-.*-ef$ ]]; then
            branch_type="feature"
        fi
        
        local worktree_info_json
        worktree_info_json=$(cat <<EOF
{
    "branch_name": "$branch_name",
    "branch_type": "$branch_type",
    "worktree_path": "$worktree_path",
    "exists": $([ -d "$worktree_path" ] && echo "true" || echo "false")
}
EOF
        )
        
        results=$(echo "$results" | jq --argjson info "$worktree_info_json" '. += [$info]')
    done <<< "$worktree_list"
    
    echo "$results"
}

# 分析工作树状态
worktree_module_analyze_worktrees() {
    local pattern="${1:-}"
    
    local worktree_list
    worktree_list=$(worktree_module_list_worktrees "$pattern") || return 1
    
    local analysis_results="[]"
    
    # 遍历每个工作树进行详细分析
    echo "$worktree_list" | jq -c '.[]' | while read -r worktree_info; do
        local branch_name=$(echo "$worktree_info" | jq -r '.branch_name')
        local worktree_path=$(echo "$worktree_info" | jq -r '.worktree_path')
        
        [[ -d "$worktree_path" ]] || continue
        
        # 获取详细状态
        local detailed_status
        detailed_status=$(worktree_module_get_worktree_status "$worktree_path" "$branch_name" "detailed") || continue
        
        analysis_results=$(echo "$analysis_results" | jq --argjson status "$detailed_status" '. += [$status]')
    done
    
    echo "$analysis_results"
}

# 获取工作树状态
worktree_module_get_worktree_status() {
    local worktree_path="$1"
    local branch_name="$2"
    local detail_level="${3:-summary}"
    
    # 基础状态检查
    local working_clean="false"
    local staging_clean="false"
    local branch_pushed="false"
    
    if git -C "$worktree_path" diff --quiet 2>/dev/null; then
        working_clean="true"
    fi
    
    if git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
        staging_clean="true"
    fi
    
    if git -C "$worktree_path" rev-parse "origin/$branch_name" >/dev/null 2>&1; then
        branch_pushed="true"
    fi
    
    # 根据详细级别返回信息
    case "$detail_level" in
        "summary")
            cat <<EOF
{
    "branch_name": "$branch_name",
    "worktree_path": "$worktree_path",
    "working_clean": $working_clean,
    "staging_clean": $staging_clean,
    "branch_pushed": $branch_pushed
}
EOF
            ;;
        "detailed"|"full")
            # 获取更多详细信息
            local last_commit_message=""
            local commits_ahead="0"
            local commits_behind="0"
            
            last_commit_message=$(git -C "$worktree_path" log -1 --pretty=format:"%s" 2>/dev/null || echo "")
            
            if [[ "$branch_pushed" == "true" ]]; then
                commits_ahead=$(git -C "$worktree_path" rev-list --count "origin/$branch_name..$branch_name" 2>/dev/null || echo "0")
                commits_behind=$(git -C "$worktree_path" rev-list --count "$branch_name..origin/$branch_name" 2>/dev/null || echo "0")
            fi
            
            cat <<EOF
{
    "branch_name": "$branch_name",
    "worktree_path": "$worktree_path",
    "working_clean": $working_clean,
    "staging_clean": $staging_clean,
    "branch_pushed": $branch_pushed,
    "last_commit_message": "$last_commit_message",
    "commits_ahead": $commits_ahead,
    "commits_behind": $commits_behind
}
EOF
            ;;
    esac
}

# ==============================================================================
# 工作树清理操作
# ==============================================================================

# 清理工作树
worktree_module_cleanup_worktrees() {
    local pattern="${1:-}"
    local safety_level="${2:-safe}"
    
    # 获取需要清理的工作树列表
    local cleanup_candidates
    cleanup_candidates=$(worktree_module_get_cleanup_candidates "$pattern" "$safety_level") || return 1
    
    local cleanup_results="[]"
    
    # 遍历清理候选
    echo "$cleanup_candidates" | jq -c '.[]' | while read -r candidate; do
        local branch_name=$(echo "$candidate" | jq -r '.branch_name')
        local worktree_path=$(echo "$candidate" | jq -r '.worktree_path')
        local safety_level=$(echo "$candidate" | jq -r '.safety_level')
        
        local cleanup_result
        cleanup_result=$(worktree_module_remove_worktree "$branch_name" "$safety_level")
        
        cleanup_results=$(echo "$cleanup_results" | jq --argjson result "$cleanup_result" '. += [$result]')
    done
    
    echo "$cleanup_results"
}

# 获取清理候选工作树
worktree_module_get_cleanup_candidates() {
    local pattern="${1:-}"
    local safety_level="${2:-safe}"
    
    local worktree_analysis
    worktree_analysis=$(worktree_module_analyze_worktrees "$pattern") || return 1
    
    local candidates="[]"
    
    # 根据安全级别过滤候选
    echo "$worktree_analysis" | jq -c '.[]' | while read -r worktree_status; do
        local branch_name=$(echo "$worktree_status" | jq -r '.branch_name')
        local working_clean=$(echo "$worktree_status" | jq -r '.working_clean')
        local staging_clean=$(echo "$worktree_status" | jq -r '.staging_clean')
        local branch_pushed=$(echo "$worktree_status" | jq -r '.branch_pushed')
        
        local candidate_safety="dangerous"
        
        if [[ "$working_clean" == "true" && "$staging_clean" == "true" && "$branch_pushed" == "true" ]]; then
            candidate_safety="safe"
        elif [[ "$working_clean" == "true" && "$staging_clean" == "true" ]]; then
            candidate_safety="warning"
        fi
        
        # 根据安全级别决定是否包含
        local include_candidate="false"
        case "$safety_level" in
            "safe")
                [[ "$candidate_safety" == "safe" ]] && include_candidate="true"
                ;;
            "warning")
                [[ "$candidate_safety" =~ ^(safe|warning)$ ]] && include_candidate="true"
                ;;
            "force")
                include_candidate="true"
                ;;
        esac
        
        if [[ "$include_candidate" == "true" ]]; then
            local candidate_info
            candidate_info=$(echo "$worktree_status" | jq --arg safety "$candidate_safety" '. + {safety_level: $safety}')
            candidates=$(echo "$candidates" | jq --argjson candidate "$candidate_info" '. += [$candidate]')
        fi
    done
    
    echo "$candidates"
}

# 删除单个工作树
worktree_module_remove_worktree() {
    local branch_name="$1"
    local safety_level="${2:-safe}"
    local worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
    
    # 验证工作树存在
    [[ -d "$worktree_path" ]] || {
        cat <<EOF
{
    "success": false,
    "branch_name": "$branch_name",
    "message": "工作树不存在"
}
EOF
        return 1
    }
    
    # 安全检查
    if [[ "$safety_level" == "safe" ]]; then
        if ! git -C "$worktree_path" diff --quiet 2>/dev/null || \
           ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
            cat <<EOF
{
    "success": false,
    "branch_name": "$branch_name",
    "message": "工作区或暂存区不干净，拒绝删除"
}
EOF
            return 1
        fi
    fi
    
    # 执行删除
    if git worktree remove "$worktree_path" --force; then
        cat <<EOF
{
    "success": true,
    "branch_name": "$branch_name",
    "message": "工作树删除成功"
}
EOF
    else
        cat <<EOF
{
    "success": false,
    "branch_name": "$branch_name",
    "message": "工作树删除失败"
}
EOF
        return 1
    fi
}