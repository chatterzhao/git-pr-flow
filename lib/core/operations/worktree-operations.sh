#!/bin/bash
# GPF Worktree操作层 - 纯Worktree命令执行，无业务逻辑
# 提供安全的Worktree操作原语，包含安全检查和rollback机制

set -euo pipefail

# ==============================================================================
# Worktree操作层 - 核心原语
# ==============================================================================

# Worktree创建操作
worktree_create_operation() {
    local worktree_path="$1"
    local branch_name="$2"
    local base_ref="${3:-HEAD}"
    local project_root="${4:-$(pwd)}"
    local force_create="${5:-false}"
    
    # 前置安全检查
    [[ -n "$worktree_path" && -n "$branch_name" ]] || {
        echo "❌ 错误：worktree路径和分支名不能为空" >&2
        return 1
    }
    
    # 验证项目根目录
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 错误：不是有效的Git仓库: $project_root" >&2
        return 1
    fi
    
    # 检查worktree路径是否已存在
    if [[ -e "$worktree_path" ]]; then
        if [[ "$force_create" == "true" ]]; then
            echo "⚠️ 警告：路径已存在，强制模式将删除: $worktree_path" >&2
            rm -rf "$worktree_path" 2>/dev/null || {
                echo "❌ 错误：无法删除现有路径: $worktree_path" >&2
                return 1
            }
        else
            echo "❌ 错误：worktree路径已存在: $worktree_path" >&2
            return 1
        fi
    fi
    
    # 确保父目录存在
    local parent_dir
    parent_dir=$(dirname "$worktree_path")
    [[ -d "$parent_dir" ]] || mkdir -p "$parent_dir" || {
        echo "❌ 错误：无法创建父目录: $parent_dir" >&2
        return 1
    }
    
    # 检查分支是否已存在
    local branch_exists=false
    if git -C "$project_root" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        branch_exists=true
    fi
    
    # 执行worktree创建操作
    local worktree_args=("add")
    
    # 如果分支不存在，需要创建新分支
    if [[ "$branch_exists" == "false" ]]; then
        worktree_args+=("-b" "$branch_name")
    fi
    
    worktree_args+=("$worktree_path")
    
    # 添加基础引用
    if [[ "$branch_exists" == "false" ]]; then
        worktree_args+=("$base_ref")
    else
        worktree_args+=("$branch_name")
    fi
    
    # 执行Git worktree add命令
    if git -C "$project_root" worktree "${worktree_args[@]}" >/dev/null 2>&1; then
        echo "✅ 成功创建worktree: $worktree_path ($branch_name)"
        echo "🔄 Rollback信息: git worktree remove $worktree_path" >&2
        return 0
    else
        echo "❌ 创建worktree失败: $worktree_path" >&2
        # 清理可能的残留
        [[ -e "$worktree_path" ]] && rm -rf "$worktree_path" 2>/dev/null || true
        return 1
    fi
}

# Worktree删除操作
worktree_delete_operation() {
    local worktree_path="$1"
    local project_root="${2:-$(pwd)}"
    local force_delete="${3:-false}"
    local backup_before_delete="${4:-true}"
    
    # 前置安全检查
    [[ -n "$worktree_path" ]] || {
        echo "❌ 错误：worktree路径不能为空" >&2
        return 1
    }
    
    # 验证项目根目录
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 错误：不是有效的Git仓库: $project_root" >&2
        return 1
    fi
    
    # 检查worktree是否存在
    if ! git -C "$project_root" worktree list | grep -q "$worktree_path"; then
        echo "⚠️ 警告：worktree不存在或未注册: $worktree_path"
        return 0
    fi
    
    # 安全检查：检查worktree中是否有未保存的工作
    if [[ -d "$worktree_path" && "$force_delete" != "true" ]]; then
        # 检查工作区状态
        if ! git -C "$worktree_path" diff --quiet 2>/dev/null || ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
            echo "❌ 错误：worktree中有未保存的修改，使用force_delete=true强制删除" >&2
            return 1
        fi
        
        # 检查未跟踪文件
        local untracked_count
        untracked_count=$(git -C "$worktree_path" ls-files --others --exclude-standard | wc -l | tr -d ' ')
        if [[ "$untracked_count" -gt 0 ]]; then
            echo "⚠️ 警告：worktree中有 $untracked_count 个未跟踪文件" >&2
        fi
    fi
    
    # 创建备份信息（用于rollback）
    local rollback_info=""
    if [[ -d "$worktree_path" && "$backup_before_delete" == "true" ]]; then
        local branch_name
        branch_name=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        local commit_sha
        commit_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null || echo "unknown")
        rollback_info="git worktree add $worktree_path -b $branch_name $commit_sha"
    fi
    
    # 执行删除操作
    local remove_args=("remove")
    [[ "$force_delete" == "true" ]] && remove_args+=("--force")
    remove_args+=("$worktree_path")
    
    if git -C "$project_root" worktree "${remove_args[@]}" >/dev/null 2>&1; then
        echo "✅ 成功删除worktree: $worktree_path"
        [[ -n "$rollback_info" ]] && echo "🔄 Rollback信息: $rollback_info" >&2
        return 0
    else
        echo "❌ 删除worktree失败: $worktree_path" >&2
        return 1
    fi
}

# Worktree列表操作
worktree_list_operation() {
    local project_root="${1:-$(pwd)}"
    local format="${2:-default}"  # default/porcelain/json
    
    # 验证项目根目录
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 错误：不是有效的Git仓库: $project_root" >&2
        return 1
    fi
    
    # 执行列表操作
    case "$format" in
        "porcelain")
            git -C "$project_root" worktree list --porcelain 2>/dev/null || {
                echo "❌ 获取worktree列表失败" >&2
                return 1
            }
            ;;
        "json")
            # 转换为JSON格式
            worktree_list_to_json "$project_root"
            ;;
        "default"|*)
            git -C "$project_root" worktree list 2>/dev/null || {
                echo "❌ 获取worktree列表失败" >&2
                return 1
            }
            ;;
    esac
    
    return 0
}

# Worktree修剪操作
worktree_prune_operation() {
    local project_root="${1:-$(pwd)}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"
    
    # 验证项目根目录
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ 错误：不是有效的Git仓库: $project_root" >&2
        return 1
    fi
    
    # 构造修剪参数
    local prune_args=("prune")
    [[ "$dry_run" == "true" ]] && prune_args+=("--dry-run")
    [[ "$verbose" == "true" ]] && prune_args+=("--verbose")
    
    # 执行修剪操作
    local output
    if output=$(git -C "$project_root" worktree "${prune_args[@]}" 2>&1); then
        if [[ "$dry_run" == "true" ]]; then
            echo "🔍 Dry run结果："
        else
            echo "✅ 成功修剪worktree"
        fi
        [[ -n "$output" ]] && echo "$output"
        return 0
    else
        echo "❌ 修剪worktree失败" >&2
        [[ -n "$output" ]] && echo "$output" >&2
        return 1
    fi
}

# ==============================================================================
# 辅助操作方法
# ==============================================================================

# 检查worktree是否存在
worktree_exists_check() {
    local worktree_path="$1"
    local project_root="${2:-$(pwd)}"
    
    # 验证项目根目录
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        return 1
    fi
    
    # 检查worktree是否在Git管理中
    git -C "$project_root" worktree list | grep -q "$(realpath "$worktree_path" 2>/dev/null || echo "$worktree_path")"
}

# 获取worktree信息
worktree_get_info() {
    local worktree_path="$1"
    local project_root="${2:-$(pwd)}"
    
    # 验证worktree存在
    if ! worktree_exists_check "$worktree_path" "$project_root"; then
        echo "❌ Worktree不存在: $worktree_path" >&2
        return 1
    fi
    
    # 获取worktree详细信息
    local branch_name=""
    local commit_sha=""
    local is_bare="false"
    
    if [[ -d "$worktree_path" ]]; then
        branch_name=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
        commit_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null || echo "unknown")
    else
        is_bare="true"
    fi
    
    # 输出JSON格式信息
    cat <<EOF
{
    "path": "$worktree_path",
    "branch": "$branch_name",
    "commit": "$commit_sha",
    "is_bare": $is_bare,
    "exists": $([ -d "$worktree_path" ] && echo "true" || echo "false")
}
EOF
}

# 将worktree列表转换为JSON格式
worktree_list_to_json() {
    local project_root="$1"
    
    local worktrees="[]"
    
    # 解析git worktree list --porcelain输出
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree\ (.*)$ ]]; then
            local path="${BASH_REMATCH[1]}"
            local branch=""
            local commit=""
            local is_bare="false"
            local is_detached="false"
            
            # 读取相关信息
            while IFS= read -r info_line; do
                if [[ "$info_line" =~ ^HEAD\ (.*)$ ]]; then
                    commit="${BASH_REMATCH[1]}"
                elif [[ "$info_line" =~ ^branch\ refs/heads/(.*)$ ]]; then
                    branch="${BASH_REMATCH[1]}"
                elif [[ "$info_line" == "detached" ]]; then
                    is_detached="true"
                    branch="detached"
                elif [[ "$info_line" == "bare" ]]; then
                    is_bare="true"
                elif [[ -z "$info_line" ]]; then
                    break
                fi
            done
            
            # 添加到JSON数组
            local worktree_obj
            worktree_obj=$(cat <<EOF
{
    "path": "$path",
    "branch": "$branch",
    "commit": "$commit",
    "is_bare": $is_bare,
    "is_detached": $is_detached,
    "exists": $([ -d "$path" ] && echo "true" || echo "false")
}
EOF
            )
            worktrees=$(echo "$worktrees" | jq --argjson obj "$worktree_obj" '. += [$obj]')
        fi
    done < <(git -C "$project_root" worktree list --porcelain 2>/dev/null)
    
    echo "$worktrees"
}

# 验证worktree路径安全性
worktree_validate_path() {
    local worktree_path="$1"
    
    # 检查路径格式
    [[ -n "$worktree_path" ]] || {
        echo "❌ Worktree路径不能为空" >&2
        return 1
    }
    
    # 防止路径遍历攻击
    if [[ "$worktree_path" =~ \.\./|^/ ]]; then
        echo "❌ 不安全的worktree路径: $worktree_path" >&2
        return 1
    fi
    
    # 检查保留路径
    local reserved_paths=("." ".." ".git" "node_modules" "vendor")
    local basename_path
    basename_path=$(basename "$worktree_path")
    
    for reserved in "${reserved_paths[@]}"; do
        if [[ "$basename_path" == "$reserved" ]]; then
            echo "❌ 不能使用保留路径名: $basename_path" >&2
            return 1
        fi
    done
    
    return 0
}

# 清理孤立的worktree
worktree_cleanup_orphaned() {
    local project_root="${1:-$(pwd)}"
    local dry_run="${2:-true}"
    
    echo "🔍 检查孤立的worktree..."
    
    # 获取所有注册的worktree
    local cleanup_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree\ (.*)$ ]]; then
            local path="${BASH_REMATCH[1]}"
            
            # 检查路径是否存在
            if [[ ! -d "$path" ]]; then
                cleanup_count=$((cleanup_count + 1))
                
                if [[ "$dry_run" == "true" ]]; then
                    echo "  🔸 会清理: $path"
                else
                    echo "  🧹 清理: $path"
                    git -C "$project_root" worktree remove "$path" 2>/dev/null || true
                fi
            fi
        fi
    done < <(git -C "$project_root" worktree list --porcelain 2>/dev/null)
    
    if [[ "$cleanup_count" -eq 0 ]]; then
        echo "✅ 没有发现孤立的worktree"
    else
        if [[ "$dry_run" == "true" ]]; then
            echo "🔍 发现 $cleanup_count 个孤立的worktree（dry run模式）"
        else
            echo "✅ 清理了 $cleanup_count 个孤立的worktree"
        fi
    fi
    
    return 0
}