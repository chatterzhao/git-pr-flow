#!/bin/bash
# GPF 数据验证模块 - 提供统一的安全检查和数据验证
# 本模块为所有命令提供一致的验证服务，确保操作安全性

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/git-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/environment-composite.sh"

# ==============================================================================
# 统一验证模块 - 核心方法
# ==============================================================================

# 统一验证检查接口（所有命令使用的统一入口）
validation_module_unified_check() {
    local validation_type="$1"          # git_safety/branch_safety/cleanup_safety/input_validation/environment_validation
    local validation_target="$2"        # 验证目标（分支名、路径等）
    local validation_context="$3"       # 验证上下文（命令类型、操作类型等）
    local validation_options="${4:-}"   # JSON格式的验证选项
    
    # 解析验证选项
    local strict_mode=$(echo "${validation_options:-{}}" | jq -r '.strict_mode // false')
    local skip_warnings=$(echo "${validation_options:-{}}" | jq -r '.skip_warnings // false')
    local include_suggestions=$(echo "${validation_options:-{}}" | jq -r '.include_suggestions // true')
    
    case "$validation_type" in
        "git_safety")
            validation_module_check_git_safety "$validation_target" "$validation_context" "$strict_mode"
            ;;
        "branch_safety")
            validation_module_check_branch_safety "$validation_target" "$validation_context" "$strict_mode"
            ;;
        "cleanup_safety")
            validation_module_check_cleanup_safety "$validation_target" "$validation_context" "$strict_mode"
            ;;
        "input_validation")
            validation_module_check_input_validity "$validation_target" "$validation_context" "$strict_mode"
            ;;
        "environment_validation")
            validation_module_check_environment_validity "$validation_target" "$validation_context" "$strict_mode"
            ;;
        "operation_safety")
            validation_module_check_operation_safety "$validation_target" "$validation_context" "$strict_mode"
            ;;
        *)
            echo "❌ 错误：未知的验证类型: $validation_type" >&2
            return 1
            ;;
    esac
}

# 批量验证检查（为复杂操作提供多重验证）
validation_module_batch_validation() {
    local validation_requests="$1"      # JSON数组：验证请求列表
    local fail_fast="${2:-true}"        # 是否在第一个失败时停止
    
    local validation_results="[]"
    local overall_success="true"
    local failed_count=0
    
    # 遍历验证请求
    echo "$validation_requests" | jq -c '.[]' | while read -r request; do
        local type=$(echo "$request" | jq -r '.type')
        local target=$(echo "$request" | jq -r '.target')
        local context=$(echo "$request" | jq -r '.context')
        local options=$(echo "$request" | jq -r '.options // {}')
        
        local result
        if result=$(validation_module_unified_check "$type" "$target" "$context" "$options" 2>&1); then
            validation_results=$(echo "$validation_results" | jq --argjson result "$result" '. += [$result]')
        else
            failed_count=$((failed_count + 1))
            overall_success="false"
            
            local error_result
            error_result=$(cat <<EOF
{
    "type": "$type",
    "target": "$target",
    "success": false,
    "error": "$result"
}
EOF
            )
            validation_results=$(echo "$validation_results" | jq --argjson result "$error_result" '. += [$result]')
            
            if [[ "$fail_fast" == "true" ]]; then
                break
            fi
        fi
    done
    
    # 返回批量验证结果
    cat <<EOF
{
    "overall_success": $overall_success,
    "failed_count": $failed_count,
    "results": $validation_results
}
EOF
}

# 安全级别评估（为clean命令提供风险评估）
validation_module_assess_safety_level() {
    local target_identifier="$1"        # 分支名或目标
    local operation_type="$2"           # cleanup/delete/merge等
    local assessment_context="$3"       # 评估上下文
    
    local safety_score=100
    local safety_level="safe"
    local safety_color="🟢"
    local risk_factors="[]"
    local safety_recommendations="[]"
    
    # Git状态检查
    local git_safety
    git_safety=$(validation_module_check_git_safety "$target_identifier" "$assessment_context" "false" 2>/dev/null) || {
        safety_score=$((safety_score - 30))
        risk_factors=$(echo "$risk_factors" | jq '. += ["Git状态不安全"]')
    }
    
    # 分支安全检查
    local branch_safety
    branch_safety=$(validation_module_check_branch_safety "$target_identifier" "$assessment_context" "false" 2>/dev/null) || {
        safety_score=$((safety_score - 40))
        risk_factors=$(echo "$risk_factors" | jq '. += ["分支状态存在风险"]')
    }
    
    # 根据分数确定安全级别
    if [[ $safety_score -ge 80 ]]; then
        safety_level="safe"
        safety_color="🟢"
        safety_recommendations=$(echo "$safety_recommendations" | jq '. += ["可以安全执行操作"]')
    elif [[ $safety_score -ge 50 ]]; then
        safety_level="warning"
        safety_color="🟡"
        safety_recommendations=$(echo "$safety_recommendations" | jq '. += ["建议谨慎操作，确认后可执行"]')
    else
        safety_level="dangerous"
        safety_color="🔴"
        safety_recommendations=$(echo "$safety_recommendations" | jq '. += ["强烈建议不要执行，可能导致数据丢失"]')
    fi
    
    cat <<EOF
{
    "target": "$target_identifier",
    "operation_type": "$operation_type",
    "safety_score": $safety_score,
    "safety_level": "$safety_level",
    "safety_color": "$safety_color",
    "risk_factors": $risk_factors,
    "recommendations": $safety_recommendations,
    "assessment_context": "$assessment_context"
}
EOF
}

# ==============================================================================
# 具体验证实现
# ==============================================================================

# Git安全检查
validation_module_check_git_safety() {
    local target="$1"
    local context="$2"
    local strict_mode="$3"
    
    local validation_issues="[]"
    local validation_warnings="[]"
    local is_safe="true"
    
    # 确定工作树路径
    local worktree_path
    if [[ "$target" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
        worktree_path="$PROJECT_ROOT/.worktrees/$target"
    else
        worktree_path="$PROJECT_ROOT"
    fi
    
    # 检查路径存在性
    if [[ ! -d "$worktree_path" ]]; then
        validation_issues=$(echo "$validation_issues" | jq '. += ["工作树路径不存在"]')
        is_safe="false"
    else
        # 检查工作区状态
        if ! git -C "$worktree_path" diff --quiet 2>/dev/null; then
            if [[ "$strict_mode" == "true" ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["工作区有未保存的修改"]')
                is_safe="false"
            else
                validation_warnings=$(echo "$validation_warnings" | jq '. += ["工作区有未保存的修改"]')
            fi
        fi
        
        # 检查暂存区状态
        if ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
            if [[ "$strict_mode" == "true" ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["暂存区有未提交的修改"]')
                is_safe="false"
            else
                validation_warnings=$(echo "$validation_warnings" | jq '. += ["暂存区有未提交的修改"]')
            fi
        fi
        
        # 检查未跟踪文件
        local untracked_count
        untracked_count=$(git -C "$worktree_path" ls-files --others --exclude-standard | wc -l | tr -d ' ')
        if [[ "$untracked_count" -gt 0 ]]; then
            validation_warnings=$(echo "$validation_warnings" | jq --arg count "$untracked_count" '. += ["有 " + $count + " 个未跟踪文件"]')
        fi
    fi
    
    cat <<EOF
{
    "validation_type": "git_safety",
    "target": "$target",
    "context": "$context",
    "is_safe": $is_safe,
    "strict_mode": $strict_mode,
    "issues": $validation_issues,
    "warnings": $validation_warnings,
    "worktree_path": "$worktree_path"
}
EOF
}

# 分支安全检查
validation_module_check_branch_safety() {
    local target="$1"
    local context="$2"
    local strict_mode="$3"
    
    local validation_issues="[]"
    local validation_warnings="[]"
    local is_safe="true"
    
    # 确定工作树路径
    local worktree_path
    if [[ "$target" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
        worktree_path="$PROJECT_ROOT/.worktrees/$target"
    else
        worktree_path="$PROJECT_ROOT"
    fi
    
    if [[ -d "$worktree_path" ]]; then
        # 检查分支是否存在
        if ! git -C "$worktree_path" rev-parse --verify "$target" >/dev/null 2>&1; then
            validation_issues=$(echo "$validation_issues" | jq '. += ["分支不存在"]')
            is_safe="false"
        else
            # 检查分支是否已推送
            if ! git -C "$worktree_path" rev-parse --verify "origin/$target" >/dev/null 2>&1; then
                validation_warnings=$(echo "$validation_warnings" | jq '. += ["分支未推送到远程"]')
            fi
            
            # 检查分支是否有未推送的提交
            local unpushed_commits
            unpushed_commits=$(git -C "$worktree_path" rev-list --count "origin/$target..$target" 2>/dev/null || echo "0")
            if [[ "$unpushed_commits" -gt 0 ]]; then
                validation_warnings=$(echo "$validation_warnings" | jq --arg count "$unpushed_commits" '. += ["有 " + $count + " 个未推送的提交"]')
            fi
            
            # 根据上下文进行特定检查
            case "$context" in
                "clean"|"delete")
                    # 对于清理操作，检查分支是否已合并
                    local merge_status
                    merge_status=$(validation_module_check_merge_status "$target" "$worktree_path")
                    local is_merged=$(echo "$merge_status" | jq -r '.is_merged')
                    
                    if [[ "$is_merged" != "true" ]]; then
                        if [[ "$strict_mode" == "true" ]]; then
                            validation_issues=$(echo "$validation_issues" | jq '. += ["分支未合并到主分支"]')
                            is_safe="false"
                        else
                            validation_warnings=$(echo "$validation_warnings" | jq '. += ["分支未合并到主分支"]')
                        fi
                    fi
                    ;;
                "pr")
                    # 对于PR操作，检查分支是否基于最新代码
                    local sync_status
                    sync_status=$(validation_module_check_sync_freshness "$target" "$worktree_path")
                    local is_fresh=$(echo "$sync_status" | jq -r '.is_fresh')
                    
                    if [[ "$is_fresh" != "true" ]]; then
                        validation_warnings=$(echo "$validation_warnings" | jq '. += ["分支不是基于最新代码"]')
                    fi
                    ;;
            esac
        fi
    else
        validation_issues=$(echo "$validation_issues" | jq '. += ["工作树不存在"]')
        is_safe="false"
    fi
    
    cat <<EOF
{
    "validation_type": "branch_safety",
    "target": "$target",
    "context": "$context",
    "is_safe": $is_safe,
    "strict_mode": $strict_mode,
    "issues": $validation_issues,
    "warnings": $validation_warnings,
    "worktree_path": "$worktree_path"
}
EOF
}

# 清理安全检查
validation_module_check_cleanup_safety() {
    local target="$1"
    local context="$2"
    local strict_mode="$3"
    
    # 组合Git安全和分支安全检查
    local git_safety
    git_safety=$(validation_module_check_git_safety "$target" "clean" "$strict_mode")
    
    local branch_safety
    branch_safety=$(validation_module_check_branch_safety "$target" "clean" "$strict_mode")
    
    # 合并检查结果
    local git_safe=$(echo "$git_safety" | jq -r '.is_safe')
    local branch_safe=$(echo "$branch_safety" | jq -r '.is_safe')
    local overall_safe="true"
    
    if [[ "$git_safe" != "true" || "$branch_safe" != "true" ]]; then
        overall_safe="false"
    fi
    
    # 合并问题和警告
    local all_issues=$(echo "$git_safety $branch_safety" | jq -s 'map(.issues) | add')
    local all_warnings=$(echo "$git_safety $branch_safety" | jq -s 'map(.warnings) | add')
    
    cat <<EOF
{
    "validation_type": "cleanup_safety",
    "target": "$target",
    "context": "$context",
    "is_safe": $overall_safe,
    "strict_mode": $strict_mode,
    "issues": $all_issues,
    "warnings": $all_warnings,
    "git_safety": $git_safety,
    "branch_safety": $branch_safety
}
EOF
}

# 输入有效性检查
validation_module_check_input_validity() {
    local input_value="$1"
    local context="$2"
    local strict_mode="$3"
    
    local validation_issues="[]"
    local validation_warnings="[]"
    local is_valid="true"
    
    case "$context" in
        "epic_name"|"feature_name")
            # 名称格式验证
            if ! validate_name_format "$input_value"; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["名称格式不正确"]')
                is_valid="false"
            fi
            
            # 长度检查
            local name_length=${#input_value}
            if [[ $name_length -lt 2 ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["名称太短，至少2个字符"]')
                is_valid="false"
            elif [[ $name_length -gt 50 ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["名称太长，最多50个字符"]')
                is_valid="false"
            fi
            
            # 特殊字符检查
            if [[ "$input_value" =~ [^a-zA-Z0-9_-] ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["包含不允许的特殊字符"]')
                is_valid="false"
            fi
            ;;
        "branch_name")
            # 分支名称验证
            if [[ ! "$input_value" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["分支名称包含无效字符"]')
                is_valid="false"
            fi
            ;;
        "file_path")
            # 文件路径验证
            if [[ "$input_value" =~ \.\./|^/ ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["路径包含不安全的元素"]')
                is_valid="false"
            fi
            ;;
    esac
    
    cat <<EOF
{
    "validation_type": "input_validation",
    "input_value": "$input_value",
    "context": "$context",
    "is_valid": $is_valid,
    "strict_mode": $strict_mode,
    "issues": $validation_issues,
    "warnings": $validation_warnings
}
EOF
}

# 环境有效性检查
validation_module_check_environment_validity() {
    local target="$1"
    local context="$2"
    local strict_mode="$3"
    
    local validation_issues="[]"
    local validation_warnings="[]"
    local is_valid="true"
    
    # 检查当前环境
    local current_env
    current_env=$(environment_detect_complete 2>/dev/null) || {
        validation_issues=$(echo "$validation_issues" | jq '. += ["无法检测当前环境"]')
        is_valid="false"
    }
    
    # 根据上下文验证环境
    case "$context" in
        "epic_operation")
            if [[ "$current_env" != "epic" && "$current_env" != "root" ]]; then
                validation_warnings=$(echo "$validation_warnings" | jq '. += ["当前不在Epic环境中"]')
            fi
            ;;
        "feature_operation")
            if [[ "$current_env" != "feature" && "$current_env" != "epic" ]]; then
                validation_warnings=$(echo "$validation_warnings" | jq '. += ["当前不在Feature环境中"]')
            fi
            ;;
        "pr_operation")
            if [[ "$current_env" != "epic" && "$current_env" != "feature" ]]; then
                if [[ "$strict_mode" == "true" ]]; then
                    validation_issues=$(echo "$validation_issues" | jq '. += ["PR操作必须在Epic或Feature环境中执行"]')
                    is_valid="false"
                else
                    validation_warnings=$(echo "$validation_warnings" | jq '. += ["建议在Epic或Feature环境中执行PR操作"]')
                fi
            fi
            ;;
    esac
    
    # 检查必要的工具
    local missing_tools="[]"
    
    if ! command -v git >/dev/null 2>&1; then
        missing_tools=$(echo "$missing_tools" | jq '. += ["git"]')
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_tools=$(echo "$missing_tools" | jq '. += ["jq"]')
    fi
    
    if [[ "$context" =~ github|pr ]] && ! command -v gh >/dev/null 2>&1; then
        missing_tools=$(echo "$missing_tools" | jq '. += ["gh"]')
    fi
    
    local missing_count
    missing_count=$(echo "$missing_tools" | jq 'length')
    if [[ $missing_count -gt 0 ]]; then
        validation_issues=$(echo "$validation_issues" | jq --argjson tools "$missing_tools" '. += ["缺少必要工具: " + ($tools | join(", "))]')
        is_valid="false"
    fi
    
    cat <<EOF
{
    "validation_type": "environment_validation",
    "target": "$target",
    "context": "$context",
    "current_environment": "$current_env",
    "is_valid": $is_valid,
    "strict_mode": $strict_mode,
    "issues": $validation_issues,
    "warnings": $validation_warnings,
    "missing_tools": $missing_tools
}
EOF
}

# 操作安全检查
validation_module_check_operation_safety() {
    local operation="$1"
    local context="$2"
    local strict_mode="$3"
    
    local validation_issues="[]"
    local validation_warnings="[]"
    local is_safe="true"
    local requires_confirmation="false"
    
    case "$operation" in
        "delete_branch"|"delete_worktree")
            requires_confirmation="true"
            validation_warnings=$(echo "$validation_warnings" | jq '. += ["删除操作不可逆，请确认"]')
            ;;
        "force_push")
            requires_confirmation="true"
            validation_warnings=$(echo "$validation_warnings" | jq '. += ["强制推送可能覆盖远程提交"]')
            ;;
        "merge_without_review")
            if [[ "$strict_mode" == "true" ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["严格模式下不允许未审查合并"]')
                is_safe="false"
            else
                validation_warnings=$(echo "$validation_warnings" | jq '. += ["建议进行代码审查后再合并"]')
            fi
            ;;
        "clean_untracked")
            requires_confirmation="true"
            validation_warnings=$(echo "$validation_warnings" | jq '. += ["将删除所有未跟踪文件"]')
            ;;
    esac
    
    cat <<EOF
{
    "validation_type": "operation_safety",
    "operation": "$operation",
    "context": "$context",
    "is_safe": $is_safe,
    "requires_confirmation": $requires_confirmation,
    "strict_mode": $strict_mode,
    "issues": $validation_issues,
    "warnings": $validation_warnings
}
EOF
}

# ==============================================================================
# 辅助验证方法
# ==============================================================================

# 检查合并状态
validation_module_check_merge_status() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 检查是否已合并到develop
    local is_merged="false"
    local merge_target="develop"
    
    if git -C "$worktree_path" merge-base --is-ancestor "$branch_name" "origin/$merge_target" 2>/dev/null; then
        is_merged="true"
    fi
    
    cat <<EOF
{
    "branch_name": "$branch_name",
    "merge_target": "$merge_target",
    "is_merged": $is_merged
}
EOF
}

# 检查同步新鲜度
validation_module_check_sync_freshness() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 检查分支是否基于最新的目标分支
    local target_branch
    if [[ "$branch_name" =~ ^epic-.*-e$ ]]; then
        target_branch="develop"
    elif [[ "$branch_name" =~ ^epic-(.+)-e-.*-ef$ ]]; then
        target_branch="epic-${BASH_REMATCH[1]}-e"
    else
        target_branch="develop"
    fi
    
    local commits_behind
    commits_behind=$(git -C "$worktree_path" rev-list --count "$branch_name..origin/$target_branch" 2>/dev/null || echo "0")
    
    local is_fresh="true"
    if [[ "$commits_behind" -gt 0 ]]; then
        is_fresh="false"
    fi
    
    cat <<EOF
{
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "commits_behind": $commits_behind,
    "is_fresh": $is_fresh
}
EOF
}