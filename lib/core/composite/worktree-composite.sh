#!/bin/bash
# GPF Core - Worktree Management Composite Methods
# 工作树管理组合方法 - 组合原子方法实现复杂逻辑

set -euo pipefail

# 导入依赖的原子方法
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/worktree-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/git-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/environment-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/platform-utils.sh"

# 智能查找或创建worktree
# 参数：(branch_name, optional: project_root)
# 返回：0（成功）或1（失败），worktree路径输出到stdout
worktree_find_or_create() {
    local branch_name="$1"
    local project_root="${2:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 首先检查worktree是否已存在
    local existing_path
    if existing_path=$(worktree_find_by_branch "$branch_name" "$project_root" 2>/dev/null); then
        # 验证现有worktree是否有效
        if worktree_validate_path "$existing_path"; then
            echo "✅ 找到现有worktree：$existing_path"
            echo "$existing_path"
            return 0
        else
            echo "⚠️ 发现无效的worktree，将重新创建：$existing_path" >&2
            # 尝试清理无效的worktree
            git -C "$project_root" worktree remove "$existing_path" --force 2>/dev/null || true
        fi
    fi
    
    # 生成标准worktree路径
    local worktree_path
    worktree_path=$(worktree_generate_path "$branch_name" "$project_root")
    
    # 确保.worktrees目录存在
    local worktrees_dir
    worktrees_dir=$(dirname "$worktree_path")
    if [[ ! -d "$worktrees_dir" ]]; then
        echo "📁 创建worktrees目录：$worktrees_dir"
        mkdir -p "$worktrees_dir" || {
            echo "❌ 错误：无法创建目录 $worktrees_dir" >&2
            return 1
        }
    fi
    
    # 检查目标路径是否为空
    if [[ -d "$worktree_path" ]] && ! worktree_check_directory_empty "$worktree_path"; then
        echo "❌ 错误：目标路径不为空：$worktree_path" >&2
        return 1
    fi
    
    # 检查分支是否存在
    local branch_exists="false"
    if git -C "$project_root" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        branch_exists="true"
        echo "🔄 使用现有分支：$branch_name"
    else
        echo "🆕 将创建新分支：$branch_name"
    fi
    
    # 创建worktree
    echo "🏗️ 创建worktree：$worktree_path"
    if [[ "$branch_exists" == "true" ]]; then
        # 从现有分支创建worktree
        if ! git -C "$project_root" worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
            echo "❌ 错误：无法从现有分支创建worktree" >&2
            return 1
        fi
    else
        # 创建新分支和worktree
        if ! git -C "$project_root" worktree add -b "$branch_name" "$worktree_path" 2>/dev/null; then
            echo "❌ 错误：无法创建新分支和worktree" >&2
            return 1
        fi
    fi
    
    # 验证创建结果
    if worktree_validate_path "$worktree_path"; then
        echo "✅ 成功创建worktree：$worktree_path"
        echo "$worktree_path"
        return 0
    else
        echo "❌ 错误：worktree创建后验证失败" >&2
        return 1
    fi
}

# 安全删除worktree
# 参数：(branch_name, optional: project_root, optional: force)
# force: "true" | "false" (默认false)
# 返回：0（成功）或1（失败）
worktree_safe_delete() {
    local branch_name="$1"
    local project_root="${2:-}"
    local force="${3:-false}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 查找worktree路径
    local worktree_path
    if ! worktree_path=$(worktree_find_by_branch "$branch_name" "$project_root"); then
        echo "⚠️ 警告：未找到分支 $branch_name 的worktree" >&2
        return 0  # 不存在就不需要删除
    fi
    
    echo "🔍 检查worktree安全性：$worktree_path"
    
    # 如果不是强制删除，执行安全检查
    if [[ "$force" != "true" ]]; then
        if ! worktree_check_safe_to_remove "$worktree_path"; then
            echo "❌ 错误：worktree有未保存的修改，无法安全删除" >&2
            echo "💡 提示：使用 force=true 参数强制删除，或先保存修改" >&2
            
            # 显示具体的修改信息
            if [[ -d "$worktree_path" ]]; then
                echo "📋 未保存的修改："
                git_get_modified_files "$worktree_path" | sed 's/^/  📝 /'
                git_get_staged_files "$worktree_path" | sed 's/^/  📦 /'
                git_get_untracked_files "$worktree_path" | sed 's/^/  ❓ /'
            fi
            return 1
        fi
    fi
    
    # 执行删除操作
    echo "🗑️ 删除worktree：$worktree_path"
    
    # 首先移除Git worktree记录
    if ! git -C "$project_root" worktree remove "$worktree_path" ${force:+--force} 2>/dev/null; then
        echo "❌ 错误：无法移除worktree记录" >&2
        return 1
    fi
    
    # 确保目录被完全删除
    if [[ -d "$worktree_path" ]]; then
        echo "🧹 清理残留目录：$worktree_path"
        rm -rf "$worktree_path" || {
            echo "❌ 错误：无法删除目录" >&2
            return 1
        }
    fi
    
    echo "✅ 成功删除worktree：$branch_name"
    return 0
}

# 智能切换worktree
# 参数：(target_branch, optional: project_root)
# 返回：0（成功）或1（失败），切换后的路径输出到stdout
worktree_intelligent_switch() {
    local target_branch="$1"
    local project_root="${2:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 检查当前环境
    local current_env
    current_env=$(determine_environment_type) || {
        echo "❌ 错误：无法确定当前环境类型" >&2
        return 1
    }
    
    echo "🔍 当前环境：$current_env"
    
    # 查找或创建目标worktree
    local target_path
    if ! target_path=$(worktree_find_or_create "$target_branch" "$project_root"); then
        return 1
    fi
    
    # 如果已经在目标worktree中，无需切换
    local current_path
    current_path=$(get_absolute_path "$(pwd)")
    target_path=$(get_absolute_path "$target_path")
    
    if [[ "$current_path" == "$target_path" ]]; then
        echo "✅ 已在目标worktree中：$target_branch"
        echo "$target_path"
        return 0
    fi
    
    # 验证目标worktree状态
    local worktree_status
    worktree_status=$(worktree_get_status "$target_path") || {
        echo "❌ 错误：无法获取worktree状态" >&2
        return 1
    }
    
    # 检查worktree是否有效
    local is_valid
    is_valid=$(echo "$worktree_status" | grep -o '"valid": [^,]*' | cut -d':' -f2 | tr -d ' ')
    
    if [[ "$is_valid" != "true" ]]; then
        echo "❌ 错误：目标worktree状态无效" >&2
        return 1
    fi
    
    echo "✅ 切换到worktree：$target_path"
    echo "$target_path"
    return 0
}

# 批量管理worktree
# 参数：(action, pattern, optional: project_root)
# action: "list" | "clean" | "validate"
# pattern: 匹配模式，如 "epic-*" 或 "*-ef"
# 返回：0（成功）或1（失败），结果信息输出到stdout
worktree_batch_management() {
    local action="$1"
    local pattern="$2"
    local project_root="${3:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 获取所有worktree
    local all_worktrees
    all_worktrees=$(worktree_list_all "$project_root")
    
    # 根据模式过滤
    local filtered_worktrees
    if [[ "$pattern" == "*" ]]; then
        filtered_worktrees="$all_worktrees"
    else
        filtered_worktrees=$(echo "$all_worktrees" | grep -E "^${pattern//\*/.*}:")
    fi
    
    if [[ -z "$filtered_worktrees" ]]; then
        echo "ℹ️ 没有找到匹配模式 '$pattern' 的worktree"
        return 0
    fi
    
    case "$action" in
        "list")
            echo "📋 匹配的worktree列表："
            echo "$filtered_worktrees" | while IFS=: read -r branch path; do
                local status_info
                status_info=$(worktree_get_status "$path" 2>/dev/null || echo '{"valid": false}')
                local is_valid
                is_valid=$(echo "$status_info" | grep -o '"valid": [^,]*' | cut -d':' -f2 | tr -d ' ')
                
                if [[ "$is_valid" == "true" ]]; then
                    echo "  ✅ $branch -> $path"
                else
                    echo "  ❌ $branch -> $path (无效)"
                fi
            done
            ;;
        "clean")
            echo "🧹 清理无效的worktree..."
            local cleaned_count=0
            echo "$filtered_worktrees" | while IFS=: read -r branch path; do
                if ! worktree_validate_path "$path"; then
                    echo "🗑️ 清理无效worktree：$branch"
                    git -C "$project_root" worktree remove "$path" --force 2>/dev/null || true
                    rm -rf "$path" 2>/dev/null || true
                    ((cleaned_count++))
                fi
            done
            echo "✅ 清理完成，共清理 $cleaned_count 个无效worktree"
            ;;
        "validate")
            echo "🔍 验证worktree状态..."
            local valid_count=0 invalid_count=0
            echo "$filtered_worktrees" | while IFS=: read -r branch path; do
                if worktree_validate_path "$path"; then
                    echo "  ✅ $branch"
                    ((valid_count++))
                else
                    echo "  ❌ $branch (路径：$path)"
                    ((invalid_count++))
                fi
            done
            echo "📊 验证结果：有效 $valid_count 个，无效 $invalid_count 个"
            ;;
        *)
            echo "❌ 错误：不支持的操作：$action" >&2
            echo "💡 支持的操作：list, clean, validate" >&2
            return 1
            ;;
    esac
    
    return 0
}

# 获取worktree使用统计
# 参数：(optional: project_root)
# 返回：JSON格式的统计信息
worktree_get_usage_statistics() {
    local project_root="${1:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 获取统计数据
    local total_count epic_count feature_count
    total_count=$(worktree_count_total "$project_root")
    epic_count=$(worktree_count_epics "$project_root")
    feature_count=$(worktree_count_features "$project_root")
    
    # 计算磁盘使用
    local total_size="0"
    if [[ -d "$project_root/.worktrees" ]]; then
        total_size=$(du -sh "$project_root/.worktrees" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    # 统计有效/无效worktree
    local valid_count=0 invalid_count=0
    if [[ "$total_count" -gt 0 ]]; then
        while IFS=: read -r branch path; do
            if worktree_validate_path "$path"; then
                ((valid_count++))
            else
                ((invalid_count++))
            fi
        done <<< "$(worktree_list_all "$project_root")"
    fi
    
    cat << EOF
{
    "total_worktrees": $total_count,
    "epic_worktrees": $epic_count,
    "feature_worktrees": $feature_count,
    "valid_worktrees": $valid_count,
    "invalid_worktrees": $invalid_count,
    "disk_usage": "$total_size",
    "project_root": "$project_root"
}
EOF
}