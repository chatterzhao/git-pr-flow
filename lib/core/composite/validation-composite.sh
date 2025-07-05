#!/bin/bash
# GPF Core - Validation Composite Methods
# 验证组合方法 - 组合原子方法实现复杂验证逻辑

set -euo pipefail

# 导入依赖的组合方法和原子方法
source "$(dirname "${BASH_SOURCE[0]}")/path-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/git-composite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/worktree-composite.sh"

# 验证PR准备就绪状态
# 参数：(branch_name, target_branch, optional: worktree_path)
# 返回：0（准备就绪）或1（未准备就绪），详细状态输出到stdout
validate_pr_readiness() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    echo "🔍 检查PR准备就绪状态..."
    
    # 1. 验证分支状态
    echo "📋 检查分支状态..."
    local branch_state
    if ! branch_state=$(git_validate_branch_state "$branch_name" "$worktree_path"); then
        echo "❌ 分支状态检查失败" >&2
        return 1
    fi
    
    # 提取分支状态信息
    local working_tree_clean staging_area_clean has_untracked remote_exists ahead_count
    working_tree_clean=$(echo "$branch_state" | grep -o '"working_tree_clean": [^,]*' | cut -d':' -f2 | tr -d ' ')
    staging_area_clean=$(echo "$branch_state" | grep -o '"staging_area_clean": [^,]*' | cut -d':' -f2 | tr -d ' ')
    has_untracked=$(echo "$branch_state" | grep -o '"has_untracked": [^,]*' | cut -d':' -f2 | tr -d ' ')
    remote_exists=$(echo "$branch_state" | grep -o '"remote_exists": [^,]*' | cut -d':' -f2 | tr -d ' ')
    ahead_count=$(echo "$branch_state" | grep -o '"ahead_count": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    # 检查工作区状态
    local work_status="ready"
    local work_issues=()
    
    if [[ "$working_tree_clean" != "true" ]]; then
        work_status="not_ready"
        work_issues+=("工作区有未保存的修改")
    fi
    
    if [[ "$staging_area_clean" != "true" ]]; then
        work_status="not_ready" 
        work_issues+=("暂存区有未提交的修改")
    fi
    
    if [[ "$has_untracked" == "true" ]]; then
        work_status="warning"
        work_issues+=("存在未跟踪文件")
    fi
    
    # 2. 检查推送状态
    echo "📤 检查推送状态..."
    local push_status="ready"
    local push_issues=()
    
    if [[ "$remote_exists" != "true" ]]; then
        push_status="not_ready"
        push_issues+=("分支未推送到远程")
    elif [[ "$ahead_count" -gt 0 ]]; then
        push_status="not_ready"
        push_issues+=("有本地提交未推送")
    fi
    
    # 3. 检查合并状态
    echo "🔀 检查合并状态..."
    local merge_status
    if ! merge_status=$(git_check_merge_status "$branch_name" "$target_branch" "$worktree_path"); then
        echo "❌ 合并状态检查失败" >&2
        return 1
    fi
    
    local can_merge has_conflicts
    can_merge=$(echo "$merge_status" | grep -o '"can_merge": [^,]*' | cut -d':' -f2 | tr -d ' ')
    has_conflicts=$(echo "$merge_status" | grep -o '"has_conflicts": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    local merge_check_status="ready"
    local merge_issues=()
    
    if [[ "$can_merge" != "true" ]]; then
        merge_check_status="not_ready"
        if [[ "$has_conflicts" == "true" ]]; then
            merge_issues+=("与目标分支存在冲突")
        else
            merge_issues+=("无法合并到目标分支")
        fi
    fi
    
    # 4. 综合评估
    local overall_status="ready"
    local critical_issues=()
    local warnings=()
    
    if [[ "$work_status" == "not_ready" ]]; then
        overall_status="not_ready"
        critical_issues+=("${work_issues[@]}")
    elif [[ "$work_status" == "warning" ]]; then
        warnings+=("${work_issues[@]}")
    fi
    
    if [[ "$push_status" == "not_ready" ]]; then
        overall_status="not_ready"
        critical_issues+=("${push_issues[@]}")
    fi
    
    if [[ "$merge_check_status" == "not_ready" ]]; then
        overall_status="not_ready"
        critical_issues+=("${merge_issues[@]}")
    fi
    
    # 输出结果
    cat << EOF
{
    "overall_status": "$overall_status",
    "branch_name": "$branch_name",
    "target_branch": "$target_branch",
    "checks": {
        "work_status": "$work_status",
        "push_status": "$push_status",
        "merge_status": "$merge_check_status"
    },
    "critical_issues": [$(printf '"%s",' "${critical_issues[@]}" | sed 's/,$//')]",
    "warnings": [$(printf '"%s",' "${warnings[@]}" | sed 's/,$//')]",
    "branch_state": $branch_state,
    "merge_state": $merge_status
}
EOF
    
    # 显示人类可读的结果
    if [[ "$overall_status" == "ready" ]]; then
        echo "✅ PR准备就绪！可以创建Pull Request"
        if [[ ${#warnings[@]} -gt 0 ]]; then
            echo "⚠️ 注意事项："
            printf '  - %s\n' "${warnings[@]}"
        fi
        return 0
    else
        echo "❌ PR未准备就绪，需要解决以下问题："
        printf '  - %s\n' "${critical_issues[@]}"
        return 1
    fi
}

# 验证清理安全性
# 参数：(branch_name, optional: project_root)
# 返回：0（安全）或1（不安全），安全状态输出到stdout
validate_clean_safety() {
    local branch_name="$1"
    local project_root="${2:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    echo "🔍 检查分支清理安全性..."
    
    # 1. 检查分支是否存在
    if ! git -C "$project_root" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        echo "ℹ️ 分支 $branch_name 不存在，无需清理"
        cat << EOF
{
    "safety_status": "safe",
    "branch_exists": false,
    "reason": "分支不存在"
}
EOF
        return 0
    fi
    
    # 2. 检查是否是保护分支
    local protected_branches=("main" "master" "develop" "dev")
    for protected in "${protected_branches[@]}"; do
        if [[ "$branch_name" == "$protected" ]]; then
            echo "❌ 错误：不能删除保护分支：$branch_name" >&2
            cat << EOF
{
    "safety_status": "unsafe",
    "branch_exists": true,
    "reason": "保护分支不能删除",
    "protected_branch": true
}
EOF
            return 1
        fi
    done
    
    # 3. 检查Git安全删除条件
    echo "🔒 检查Git安全删除条件..."
    local git_safe
    if git_safe=$(git_check_safe_branch_deletion "$branch_name" "$project_root" 2>&1); then
        echo "✅ Git安全检查通过"
    else
        echo "❌ Git安全检查失败" >&2
        cat << EOF
{
    "safety_status": "unsafe",
    "branch_exists": true,
    "reason": "分支未合并到主分支",
    "git_check_result": "$git_safe"
}
EOF
        return 1
    fi
    
    # 4. 检查worktree安全性
    echo "🏗️ 检查worktree安全性..."
    local worktree_path
    if worktree_path=$(worktree_find_by_branch "$branch_name" "$project_root" 2>/dev/null); then
        echo "📁 找到worktree：$worktree_path"
        
        if ! worktree_check_safe_to_remove "$worktree_path"; then
            echo "❌ worktree有未保存的修改" >&2
            cat << EOF
{
    "safety_status": "unsafe",
    "branch_exists": true,
    "worktree_exists": true,
    "worktree_path": "$worktree_path",
    "reason": "worktree有未保存的修改"
}
EOF
            return 1
        fi
        echo "✅ worktree安全检查通过"
    else
        echo "ℹ️ 未找到对应的worktree"
    fi
    
    # 5. 所有检查通过
    echo "✅ 清理安全性验证通过"
    cat << EOF
{
    "safety_status": "safe",
    "branch_exists": true,
    "protected_branch": false,
    "git_safe": true,
    "worktree_safe": true,
    "worktree_path": "${worktree_path:-null}"
}
EOF
    
    return 0
}

# 验证同步要求
# 参数：(source_branch, target_branch, optional: project_root)
# 返回：0（满足要求）或1（不满足），同步状态输出到stdout
validate_sync_requirements() {
    local source_branch="$1"
    local target_branch="$2"
    local project_root="${3:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    echo "🔍 检查同步要求..."
    
    # 1. 检查分支存在性
    local source_exists target_exists
    source_exists=$(git -C "$project_root" rev-parse --verify "$source_branch" >/dev/null 2>&1 && echo "true" || echo "false")
    target_exists=$(git -C "$project_root" rev-parse --verify "$target_branch" >/dev/null 2>&1 && echo "true" || echo "false")
    
    if [[ "$source_exists" != "true" ]]; then
        echo "❌ 错误：源分支 $source_branch 不存在" >&2
        return 1
    fi
    
    if [[ "$target_exists" != "true" ]]; then
        echo "❌ 错误：目标分支 $target_branch 不存在" >&2
        return 1
    fi
    
    # 2. 检查目标分支工作区状态
    local target_path
    if target_path=$(worktree_find_by_branch "$target_branch" "$project_root" 2>/dev/null); then
        echo "🏗️ 检查目标分支worktree状态..."
        
        if ! git_ensure_safe_state "pull" "$target_path"; then
            echo "❌ 目标分支worktree状态不安全" >&2
            cat << EOF
{
    "sync_ready": false,
    "reason": "目标分支worktree有未保存修改",
    "target_worktree": "$target_path"
}
EOF
            return 1
        fi
    fi
    
    # 3. 检查合并状态
    echo "🔀 检查合并状态..."
    local merge_status
    if ! merge_status=$(git_check_merge_status "$source_branch" "$target_branch" "$project_root"); then
        return 1
    fi
    
    local is_merged can_merge has_conflicts ahead_count
    is_merged=$(echo "$merge_status" | grep -o '"is_merged": [^,]*' | cut -d':' -f2 | tr -d ' ')
    can_merge=$(echo "$merge_status" | grep -o '"can_merge": [^,]*' | cut -d':' -f2 | tr -d ' ')
    has_conflicts=$(echo "$merge_status" | grep -o '"has_conflicts": [^,]*' | cut -d':' -f2 | tr -d ' ')
    ahead_count=$(echo "$merge_status" | grep -o '"ahead_count": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    # 4. 评估同步状态
    local sync_status="ready"
    local sync_issues=()
    
    if [[ "$is_merged" == "true" ]]; then
        sync_status="no_changes"
        echo "ℹ️ 源分支已完全合并，无需同步"
    elif [[ "$ahead_count" -eq 0 ]]; then
        sync_status="no_changes"
        echo "ℹ️ 源分支无新提交，无需同步"
    elif [[ "$has_conflicts" == "true" ]]; then
        sync_status="conflicts"
        sync_issues+=("存在合并冲突")
        echo "❌ 检测到合并冲突"
    elif [[ "$can_merge" == "true" ]]; then
        sync_status="ready"
        echo "✅ 可以安全同步"
    else
        sync_status="blocked"
        sync_issues+=("无法合并，原因未知")
    fi
    
    # 输出结果
    cat << EOF
{
    "sync_status": "$sync_status",
    "source_branch": "$source_branch",
    "target_branch": "$target_branch",
    "source_exists": $source_exists,
    "target_exists": $target_exists,
    "ahead_count": $ahead_count,
    "has_conflicts": $has_conflicts,
    "can_merge": $can_merge,
    "is_merged": $is_merged,
    "issues": [$(printf '"%s",' "${sync_issues[@]}" | sed 's/,$//')]",
    "target_worktree": "${target_path:-null}",
    "merge_details": $merge_status
}
EOF
    
    case "$sync_status" in
        "ready")
            echo "✅ 同步要求验证通过"
            return 0
            ;;
        "no_changes")
            echo "ℹ️ 无需同步"
            return 0
            ;;
        *)
            echo "❌ 同步要求验证失败"
            printf '  - %s\n' "${sync_issues[@]}"
            return 1
            ;;
    esac
}

# 综合环境验证
# 参数：(operation_type, optional: current_path)
# operation_type: "start" | "pr" | "clean" | "sync" | "status"
# 返回：0（环境就绪）或1（环境异常），环境状态输出到stdout
validate_environment_for_operation() {
    local operation_type="$1"
    local current_path="${2:-$(pwd)}"
    
    echo "🔍 验证操作环境：$operation_type"
    
    # 1. 检查项目根目录
    local project_root
    if ! project_root=$(find_project_root); then
        echo "❌ 错误：当前不在Git项目中" >&2
        return 1
    fi
    
    # 2. 检查环境类型
    local env_type
    env_type=$(determine_environment_type "$current_path")
    
    echo "📍 当前环境：$env_type"
    echo "📁 项目根目录：$project_root"
    
    # 3. 根据操作类型验证环境要求
    local env_status="valid"
    local env_issues=()
    local env_warnings=()
    
    case "$operation_type" in
        "start")
            # start命令最好在root环境执行
            if [[ "$env_type" != "root" ]]; then
                env_warnings+=("建议在项目根目录执行start命令")
            fi
            ;;
        "pr")
            # pr命令需要在epic或feature环境
            if [[ "$env_type" != "epic" && "$env_type" != "feature" ]]; then
                env_status="invalid"
                env_issues+=("PR操作需要在Epic或Feature环境中执行")
            fi
            ;;
        "clean")
            # clean命令最好在root环境执行
            if [[ "$env_type" != "root" ]]; then
                env_warnings+=("建议在项目根目录执行clean命令")
            fi
            ;;
        "sync")
            # sync命令需要明确的环境上下文
            if [[ "$env_type" == "unknown" ]]; then
                env_status="invalid"
                env_issues+=("sync操作需要明确的环境上下文")
            fi
            ;;
        "status")
            # status命令在任何环境都可以执行
            ;;
        *)
            env_status="invalid"
            env_issues+=("不支持的操作类型：$operation_type")
            ;;
    esac
    
    # 4. 检查Git仓库状态
    if ! git_check_repository_valid "$current_path"; then
        env_status="invalid"
        env_issues+=("Git仓库状态异常")
    fi
    
    # 5. 输出结果
    cat << EOF
{
    "environment_status": "$env_status",
    "operation_type": "$operation_type",
    "environment_type": "$env_type",
    "project_root": "$project_root",
    "current_path": "$current_path",
    "issues": [$(printf '"%s",' "${env_issues[@]}" | sed 's/,$//')]",
    "warnings": [$(printf '"%s",' "${env_warnings[@]}" | sed 's/,$//')]"
}
EOF
    
    # 显示结果
    if [[ "$env_status" == "valid" ]]; then
        echo "✅ 环境验证通过"
        if [[ ${#env_warnings[@]} -gt 0 ]]; then
            echo "⚠️ 建议："
            printf '  - %s\n' "${env_warnings[@]}"
        fi
        return 0
    else
        echo "❌ 环境验证失败"
        printf '  - %s\n' "${env_issues[@]}"
        return 1
    fi
}