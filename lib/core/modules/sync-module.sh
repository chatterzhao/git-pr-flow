#!/bin/bash
# GPF 同步管理模块 - 提供智能级联同步功能
# 本模块为sync/start/pr命令提供完整的分支同步服务

set -euo pipefail

# 按四层架构获取项目根目录（通过composite层）
source "$(dirname "${BASH_SOURCE[0]}")/../composite/environment-composite.sh"

# 通过composite层获取项目根目录（遵循四层架构）
PROJECT_ROOT=$(environment_get_project_root) || {
    echo "❌ 错误：无法通过composite层获取项目根目录" >&2
    exit 1
}

# 加载依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/git-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/worktree-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/environment-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"

# ==============================================================================
# 智能级联同步模块 - 核心方法
# ==============================================================================

# 智能级联同步（develop→epic→features）
sync_module_intelligent_cascade() {
    local sync_scope="${1:-auto}"        # auto/develop/epic/feature/target
    local target_identifier="${2:-}"     # Epic名称或Feature分支名（可选）
    local sync_options="${3:-}"          # JSON格式选项
    local force_mode="${4:-false}"       # 是否强制同步
    
    # 解析同步选项
    local pull_remote=$(echo "${sync_options:-{}}" | jq -r '.pull_remote // true')
    local check_conflicts=$(echo "${sync_options:-{}}" | jq -r '.check_conflicts // true')
    local cascade_down=$(echo "${sync_options:-{}}" | jq -r '.cascade_down // true')
    
    # 确定同步范围
    local sync_plan
    sync_plan=$(sync_module_determine_sync_scope "$sync_scope" "$target_identifier") || return 1
    
    # 验证同步安全性
    if [[ "$force_mode" != "true" ]]; then
        if ! sync_module_validate_sync_safety "$sync_plan"; then
            echo "❌ 错误：同步安全验证失败" >&2
            return 1
        fi
    fi
    
    # 执行级联同步
    sync_module_execute_cascade_sync "$sync_plan" "$pull_remote" "$check_conflicts" "$cascade_down"
}

# 同步就绪性检查（为pr/start命令提供服务）
sync_module_check_sync_readiness() {
    local branch_name="$1"
    local target_branch="$2"
    local check_purpose="${3:-general}"   # pr/start/general
    
    # 获取分支信息
    local branch_info
    branch_info=$(sync_module_analyze_branch_sync_status "$branch_name" "$target_branch") || return 1
    
    # 根据用途返回检查结果
    case "$check_purpose" in
        "pr")
            sync_module_format_pr_sync_status "$branch_info"
            ;;
        "start")
            sync_module_format_start_sync_status "$branch_info"
            ;;
        "general")
            sync_module_format_general_sync_status "$branch_info"
            ;;
        *)
            echo "❌ 错误：未知的同步检查目的: $check_purpose" >&2
            return 1
            ;;
    esac
}

# 单向同步操作（基础同步原语）
sync_module_single_direction_sync() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    local sync_method="${4:-merge}"       # merge/rebase/pull
    
    # 验证分支存在性
    if ! sync_module_validate_branches_exist "$source_branch" "$target_branch" "$worktree_path"; then
        echo "❌ 错误：分支验证失败" >&2
        return 1
    fi
    
    # 检查工作区状态
    if ! sync_module_check_workspace_clean "$worktree_path"; then
        echo "❌ 错误：工作区不干净，无法同步" >&2
        return 1
    fi
    
    # 执行同步操作
    case "$sync_method" in
        "merge")
            sync_module_execute_merge_sync "$source_branch" "$target_branch" "$worktree_path"
            ;;
        "rebase")
            sync_module_execute_rebase_sync "$source_branch" "$target_branch" "$worktree_path"
            ;;
        "pull")
            sync_module_execute_pull_sync "$source_branch" "$worktree_path"
            ;;
        *)
            echo "❌ 错误：未知的同步方法: $sync_method" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# 同步范围确定和规划
# ==============================================================================

# 确定同步范围
sync_module_determine_sync_scope() {
    local sync_scope="$1"
    local target_identifier="$2"
    
    case "$sync_scope" in
        "auto")
            sync_module_auto_determine_scope
            ;;
        "develop")
            echo '{"scope": "develop", "branches": ["develop"], "cascade": false}'
            ;;
        "epic")
            sync_module_plan_epic_sync "$target_identifier"
            ;;
        "feature")
            sync_module_plan_feature_sync "$target_identifier"
            ;;
        "target")
            sync_module_plan_target_sync "$target_identifier"
            ;;
        *)
            echo "❌ 错误：未知的同步范围: $sync_scope" >&2
            return 1
            ;;
    esac
}

# 自动确定同步范围
sync_module_auto_determine_scope() {
    # 检测当前环境
    local current_env
    current_env=$(environment_detect_complete) || {
        echo "❌ 错误：无法检测当前环境" >&2
        return 1
    }
    
    case "$current_env" in
        "root")
            # 在根目录，同步develop分支
            echo '{"scope": "develop", "branches": ["develop"], "cascade": false}'
            ;;
        "epic")
            # 在Epic环境，同步当前Epic
            local current_epic
            current_epic=$(extract_current_epic_name) || return 1
            sync_module_plan_epic_sync "$current_epic"
            ;;
        "feature")
            # 在Feature环境，同步当前Feature
            local current_branch
            current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
            sync_module_plan_feature_sync "$current_branch"
            ;;
        *)
            echo "❌ 错误：无法在当前环境确定同步范围: $current_env" >&2
            return 1
            ;;
    esac
}

# 规划Epic同步
sync_module_plan_epic_sync() {
    local epic_name="$1"
    
    [[ -n "$epic_name" ]] || {
        echo "❌ 错误：Epic名称不能为空" >&2
        return 1
    }
    
    local epic_branch="epic-$epic_name-e"
    
    # 查找相关的Feature分支
    local related_features
    related_features=$(sync_module_find_epic_features "$epic_name") || related_features="[]"
    
    # 生成同步计划
    cat <<EOF
{
    "scope": "epic",
    "epic_name": "$epic_name",
    "epic_branch": "$epic_branch",
    "target_branch": "develop",
    "related_features": $related_features,
    "cascade": true,
    "sync_chain": ["develop", "$epic_branch"]
}
EOF
}

# 规划Feature同步
sync_module_plan_feature_sync() {
    local feature_identifier="$1"
    
    # 解析Feature信息
    local feature_branch epic_name
    if [[ "$feature_identifier" =~ ^epic-(.+)-e-(.+)-ef$ ]]; then
        feature_branch="$feature_identifier"
        epic_name="${BASH_REMATCH[1]}"
    else
        echo "❌ 错误：无效的Feature标识: $feature_identifier" >&2
        return 1
    fi
    
    local epic_branch="epic-$epic_name-e"
    
    # 生成同步计划
    cat <<EOF
{
    "scope": "feature",
    "feature_branch": "$feature_branch",
    "epic_branch": "$epic_branch",
    "epic_name": "$epic_name",
    "target_branch": "develop",
    "cascade": true,
    "sync_chain": ["develop", "$epic_branch", "$feature_branch"]
}
EOF
}

# 规划目标同步
sync_module_plan_target_sync() {
    local target_branch="$1"
    
    [[ -n "$target_branch" ]] || {
        echo "❌ 错误：目标分支不能为空" >&2
        return 1
    }
    
    # 简单的单向同步计划
    cat <<EOF
{
    "scope": "target",
    "target_branch": "$target_branch",
    "cascade": false,
    "sync_chain": ["$target_branch"]
}
EOF
}

# ==============================================================================
# 同步安全验证
# ==============================================================================

# 验证同步安全性
sync_module_validate_sync_safety() {
    local sync_plan="$1"
    
    local scope=$(echo "$sync_plan" | jq -r '.scope')
    local sync_chain=$(echo "$sync_plan" | jq -r '.sync_chain[]' 2>/dev/null || echo "")
    
    local validation_issues="[]"
    
    # 验证同步链中的每个分支
    while IFS= read -r branch_name; do
        [[ -n "$branch_name" ]] || continue
        
        local branch_validation
        branch_validation=$(sync_module_validate_branch_safety "$branch_name") || continue
        
        local has_issues=$(echo "$branch_validation" | jq -r '.has_issues')
        if [[ "$has_issues" == "true" ]]; then
            local issues=$(echo "$branch_validation" | jq -r '.issues[]')
            while IFS= read -r issue; do
                [[ -n "$issue" ]] || continue
                validation_issues=$(echo "$validation_issues" | jq --arg issue "$branch_name: $issue" '. += [$issue]')
            done <<< "$issues"
        fi
    done <<< "$sync_chain"
    
    # 检查是否有验证问题
    local issue_count
    issue_count=$(echo "$validation_issues" | jq 'length')
    
    if [[ "$issue_count" -gt 0 ]]; then
        echo "🚨 同步安全验证发现问题："
        echo "$validation_issues" | jq -r '.[]' | while read -r issue; do
            echo "  ❌ $issue"
        done
        return 1
    fi
    
    echo "✅ 同步安全验证通过"
    return 0
}

# 验证单个分支的安全性
sync_module_validate_branch_safety() {
    local branch_name="$1"
    
    local issues="[]"
    local has_issues="false"
    
    # 确定分支位置
    local worktree_path
    if [[ "$branch_name" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
        # Epic或Feature分支
        worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
        
        if [[ ! -d "$worktree_path" ]]; then
            issues=$(echo "$issues" | jq '. += ["worktree不存在"]')
            has_issues="true"
        fi
    else
        # 其他分支（如develop）
        worktree_path="$PROJECT_ROOT"
    fi
    
    # 检查工作区状态
    if [[ -d "$worktree_path" ]]; then
        if ! sync_module_check_workspace_clean "$worktree_path"; then
            issues=$(echo "$issues" | jq '. += ["工作区不干净"]')
            has_issues="true"
        fi
        
        # 检查是否有未提交的修改
        if ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
            issues=$(echo "$issues" | jq '. += ["有未提交的暂存修改"]')
            has_issues="true"
        fi
    fi
    
    cat <<EOF
{
    "branch_name": "$branch_name",
    "worktree_path": "$worktree_path",
    "has_issues": $has_issues,
    "issues": $issues
}
EOF
}

# ==============================================================================
# 同步执行引擎
# ==============================================================================

# 执行级联同步
sync_module_execute_cascade_sync() {
    local sync_plan="$1"
    local pull_remote="$2"
    local check_conflicts="$3"
    local cascade_down="$4"
    
    local scope=$(echo "$sync_plan" | jq -r '.scope')
    local sync_chain=$(echo "$sync_plan" | jq -r '.sync_chain[]' 2>/dev/null || echo "")
    
    echo "🔄 开始执行级联同步（范围: $scope）"
    
    # 第一阶段：从远程拉取最新代码（如果启用）
    if [[ "$pull_remote" == "true" ]]; then
        sync_module_pull_remote_updates "$sync_plan"
    fi
    
    # 第二阶段：执行级联同步
    if [[ "$cascade_down" == "true" ]]; then
        sync_module_execute_downward_cascade "$sync_plan" "$check_conflicts"
    else
        sync_module_execute_single_sync "$sync_plan"
    fi
    
    echo "✅ 级联同步完成"
}

# 从远程拉取更新
sync_module_pull_remote_updates() {
    local sync_plan="$1"
    
    local scope=$(echo "$sync_plan" | jq -r '.scope')
    
    echo "📥 从远程拉取最新更新..."
    
    case "$scope" in
        "develop")
            # 只更新develop分支
            sync_module_pull_branch_from_remote "develop" "$PROJECT_ROOT"
            ;;
        "epic"|"feature")
            # 更新develop和相关分支
            sync_module_pull_branch_from_remote "develop" "$PROJECT_ROOT"
            
            local target_branch=$(echo "$sync_plan" | jq -r '.epic_branch // .feature_branch')
            if [[ -n "$target_branch" && "$target_branch" != "null" ]]; then
                local worktree_path="$PROJECT_ROOT/.worktrees/$target_branch"
                if [[ -d "$worktree_path" ]]; then
                    sync_module_pull_branch_from_remote "$target_branch" "$worktree_path"
                fi
            fi
            ;;
    esac
}

# 执行向下级联
sync_module_execute_downward_cascade() {
    local sync_plan="$1"
    local check_conflicts="$2"
    
    local sync_chain=$(echo "$sync_plan" | jq -r '.sync_chain[]' 2>/dev/null || echo "")
    local previous_branch=""
    
    while IFS= read -r current_branch; do
        [[ -n "$current_branch" ]] || continue
        
        if [[ -n "$previous_branch" ]]; then
            echo "🔄 同步 $previous_branch → $current_branch"
            
            # 确定工作树路径
            local target_worktree
            if [[ "$current_branch" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
                target_worktree="$PROJECT_ROOT/.worktrees/$current_branch"
            else
                target_worktree="$PROJECT_ROOT"
            fi
            
            # 执行同步
            if sync_module_single_direction_sync "$previous_branch" "$current_branch" "$target_worktree" "merge"; then
                echo "  ✅ $current_branch 同步成功"
            else
                echo "  ❌ $current_branch 同步失败"
                return 1
            fi
        fi
        
        previous_branch="$current_branch"
    done <<< "$sync_chain"
}

# 执行单个同步
sync_module_execute_single_sync() {
    local sync_plan="$1"
    
    local target_branch=$(echo "$sync_plan" | jq -r '.target_branch // .sync_chain[0]')
    local worktree_path
    
    if [[ "$target_branch" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
        worktree_path="$PROJECT_ROOT/.worktrees/$target_branch"
    else
        worktree_path="$PROJECT_ROOT"
    fi
    
    sync_module_pull_branch_from_remote "$target_branch" "$worktree_path"
}

# ==============================================================================
# 同步操作原语
# ==============================================================================

# 从远程拉取分支
sync_module_pull_branch_from_remote() {
    local branch_name="$1"
    local worktree_path="$2"
    
    if [[ ! -d "$worktree_path" ]]; then
        echo "⚠️ 工作树不存在，跳过: $worktree_path" >&2
        return 0
    fi
    
    # 检查当前分支
    local current_branch
    current_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
        echo "❌ 无法获取当前分支: $worktree_path" >&2
        return 1
    }
    
    # 切换到目标分支（如果需要）
    if [[ "$current_branch" != "$branch_name" ]]; then
        git -C "$worktree_path" checkout "$branch_name" >/dev/null 2>&1 || {
            echo "❌ 无法切换到分支: $branch_name" >&2
            return 1
        }
    fi
    
    # 拉取最新代码
    if git -C "$worktree_path" pull origin "$branch_name" >/dev/null 2>&1; then
        echo "  📥 $branch_name 拉取成功"
        return 0
    else
        echo "  ❌ $branch_name 拉取失败"
        return 1
    fi
}

# 执行合并同步
sync_module_execute_merge_sync() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    
    # 切换到目标分支
    git -C "$worktree_path" checkout "$target_branch" >/dev/null 2>&1 || return 1
    
    # 执行合并
    if git -C "$worktree_path" merge "origin/$source_branch" --no-edit >/dev/null 2>&1; then
        return 0
    else
        echo "❌ 合并冲突，需要手动解决" >&2
        return 1
    fi
}

# 执行变基同步
sync_module_execute_rebase_sync() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    
    # 切换到目标分支
    git -C "$worktree_path" checkout "$target_branch" >/dev/null 2>&1 || return 1
    
    # 执行变基
    if git -C "$worktree_path" rebase "origin/$source_branch" >/dev/null 2>&1; then
        return 0
    else
        echo "❌ 变基冲突，需要手动解决" >&2
        return 1
    fi
}

# ==============================================================================
# 辅助方法
# ==============================================================================

# 检查工作区是否干净
sync_module_check_workspace_clean() {
    local worktree_path="$1"
    
    [[ -d "$worktree_path" ]] || return 1
    
    # 检查未暂存修改
    git -C "$worktree_path" diff --quiet 2>/dev/null || return 1
    
    # 检查已暂存修改
    git -C "$worktree_path" diff --cached --quiet 2>/dev/null || return 1
    
    return 0
}

# 验证分支存在性
sync_module_validate_branches_exist() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="$3"
    
    # 检查目标分支存在
    git -C "$worktree_path" rev-parse --verify "$target_branch" >/dev/null 2>&1 || {
        echo "❌ 目标分支不存在: $target_branch" >&2
        return 1
    }
    
    # 检查源分支存在（远程）
    git -C "$worktree_path" rev-parse --verify "origin/$source_branch" >/dev/null 2>&1 || {
        echo "❌ 源分支不存在: origin/$source_branch" >&2
        return 1
    }
    
    return 0
}

# 查找Epic相关的Feature分支
sync_module_find_epic_features() {
    local epic_name="$1"
    
    local features="[]"
    local worktree_base="$PROJECT_ROOT/.worktrees"
    
    [[ -d "$worktree_base" ]] || {
        echo "$features"
        return 0
    }
    
    find "$worktree_base" -maxdepth 1 -type d -name "epic-$epic_name-e-*-ef" 2>/dev/null | while read -r feature_dir; do
        local feature_branch=$(basename "$feature_dir")
        features=$(echo "$features" | jq --arg branch "$feature_branch" '. += [$branch]')
    done
    
    echo "$features"
}

# 分析分支同步状态
sync_module_analyze_branch_sync_status() {
    local branch_name="$1"
    local target_branch="$2"
    
    # 确定工作树路径
    local worktree_path
    if [[ "$branch_name" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
        worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
    else
        worktree_path="$PROJECT_ROOT"
    fi
    
    # 获取同步状态信息
    local commits_behind="0"
    local commits_ahead="0"
    local needs_sync="false"
    
    if [[ -d "$worktree_path" ]]; then
        commits_behind=$(git -C "$worktree_path" rev-list --count "$branch_name..origin/$target_branch" 2>/dev/null || echo "0")
        commits_ahead=$(git -C "$worktree_path" rev-list --count "origin/$target_branch..$branch_name" 2>/dev/null || echo "0")
        
        if [[ "$commits_behind" -gt 0 ]]; then
            needs_sync="true"
        fi
    fi
    
    cat <<EOF
{
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "worktree_path": "$worktree_path",
    "commits_behind": $commits_behind,
    "commits_ahead": $commits_ahead,
    "needs_sync": $needs_sync
}
EOF
}

# 格式化PR同步状态
sync_module_format_pr_sync_status() {
    local branch_info="$1"
    
    local needs_sync=$(echo "$branch_info" | jq -r '.needs_sync')
    local commits_behind=$(echo "$branch_info" | jq -r '.commits_behind')
    
    local sync_ready="true"
    local blocking_issues="[]"
    
    if [[ "$needs_sync" == "true" ]]; then
        sync_ready="false"
        blocking_issues=$(echo "$blocking_issues" | jq --arg issue "分支落后 $commits_behind 个提交" '. += [$issue]')
    fi
    
    cat <<EOF
{
    "purpose": "pr",
    "sync_ready": $sync_ready,
    "blocking_issues": $blocking_issues,
    "branch_info": $branch_info
}
EOF
}

# 格式化start同步状态
sync_module_format_start_sync_status() {
    local branch_info="$1"
    
    local needs_sync=$(echo "$branch_info" | jq -r '.needs_sync')
    
    cat <<EOF
{
    "purpose": "start",
    "epic_sync_recommended": $needs_sync,
    "branch_info": $branch_info
}
EOF
}

# 格式化通用同步状态
sync_module_format_general_sync_status() {
    local branch_info="$1"
    
    cat <<EOF
{
    "purpose": "general",
    "branch_info": $branch_info
}
EOF
}