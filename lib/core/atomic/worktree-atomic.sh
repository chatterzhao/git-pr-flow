#!/bin/bash
# GPF Core - Worktree Operations Atomic Methods
# Worktree操作原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 列出所有现有的worktree
# 参数：(optional: project_root)
# 返回：每行格式为 "branch:path"
worktree_list_all() {
    local project_root="${1:-$(pwd)}"
    
    git -C "$project_root" worktree list --porcelain 2>/dev/null | \
    awk '
        /^worktree/ {path=$2} 
        /^branch/ {branch=$2} 
        /^$/ {
            if(branch && path) {
                print branch":"path
                branch=""
                path=""
            }
        }
        END {
            if(branch && path) {
                print branch":"path
            }
        }
    '
}

# 根据分支名查找worktree路径
# 参数：(target_branch, optional: project_root)
# 返回：worktree路径 或 返回码1（未找到）
worktree_find_by_branch() {
    local target_branch="$1"
    local project_root="${2:-$(pwd)}"
    
    worktree_list_all "$project_root" | while IFS=: read -r branch path; do
        if [[ "$branch" == "$target_branch" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# 检查worktree是否存在
# 参数：(branch_name, optional: project_root)
# 返回：0（存在）或1（不存在）
worktree_exists() {
    local branch_name="$1"
    local project_root="${2:-$(pwd)}"
    
    worktree_find_by_branch "$branch_name" "$project_root" >/dev/null 2>&1
}

# 获取worktree所在的分支名
# 参数：(worktree_path)
# 返回：分支名 或 返回码1（无效路径）
worktree_get_branch() {
    local worktree_path="$1"
    
    if [[ -d "$worktree_path" ]]; then
        git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null
    else
        return 1
    fi
}

# 检查worktree路径是否有效
# 参数：(worktree_path)
# 返回：0（有效）或1（无效）
worktree_validate_path() {
    local worktree_path="$1"
    
    [[ -d "$worktree_path" ]] && git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1
}

# 生成标准worktree路径
# 参数：(branch_name, project_root)
# 返回：标准worktree路径
worktree_generate_path() {
    local branch_name="$1"
    local project_root="$2"
    
    echo "$project_root/.worktrees/$branch_name"
}

# 检查worktree目录是否为空
# 参数：(worktree_path)
# 返回：0（为空或不存在）或1（非空）
worktree_check_directory_empty() {
    local worktree_path="$1"
    
    if [[ ! -d "$worktree_path" ]]; then
        return 0  # 不存在视为空
    fi
    
    # 检查目录是否为空（忽略隐藏文件）
    local file_count
    file_count=$(find "$worktree_path" -maxdepth 1 -type f | wc -l)
    [[ "$file_count" -eq 0 ]]
}

# 获取worktree的状态信息
# 参数：(worktree_path)
# 返回：JSON格式的状态信息
worktree_get_status() {
    local worktree_path="$1"
    
    if ! worktree_validate_path "$worktree_path"; then
        cat << EOF
{
    "valid": false,
    "exists": false,
    "branch": null,
    "clean": false,
    "error": "Invalid worktree path"
}
EOF
        return 1
    fi
    
    local branch_name
    branch_name=$(worktree_get_branch "$worktree_path") || branch_name="unknown"
    
    local is_clean="false"
    if git_check_working_tree_clean "$worktree_path" && git_check_staging_area_clean "$worktree_path"; then
        is_clean="true"
    fi
    
    cat << EOF
{
    "valid": true,
    "exists": true,
    "branch": "$branch_name",
    "clean": $is_clean,
    "path": "$worktree_path"
}
EOF
}

# 检查是否可以安全删除worktree
# 参数：(worktree_path)
# 返回：0（可安全删除）或1（不安全）
worktree_check_safe_to_remove() {
    local worktree_path="$1"
    
    if ! worktree_validate_path "$worktree_path"; then
        return 0  # 无效路径可以删除
    fi
    
    # 检查工作区和暂存区是否干净
    if ! git_check_working_tree_clean "$worktree_path"; then
        return 1  # 有未保存修改
    fi
    
    if ! git_check_staging_area_clean "$worktree_path"; then
        return 1  # 有未提交修改
    fi
    
    return 0
}

# 获取所有Epic类型的worktree
# 参数：(optional: project_root)
# 返回：Epic worktree列表，每行格式为 "branch:path"
worktree_list_epics() {
    local project_root="${1:-$(pwd)}"
    
    worktree_list_all "$project_root" | grep -E '^epic-.*-e:'
}

# 获取所有Feature类型的worktree
# 参数：(optional: project_root)
# 返回：Feature worktree列表，每行格式为 "branch:path"
worktree_list_features() {
    local project_root="${1:-$(pwd)}"
    
    worktree_list_all "$project_root" | grep -E '^epic-.*-ef:'
}

# 根据Epic名称获取相关的Feature worktree
# 参数：(epic_name, optional: project_root)
# 返回：相关Feature worktree列表，每行格式为 "branch:path"
worktree_list_features_for_epic() {
    local epic_name="$1"
    local project_root="${2:-$(pwd)}"
    
    worktree_list_features "$project_root" | grep -E "^epic-$epic_name-e-.*-ef:"
}

# 计算worktree总数
# 参数：(optional: project_root)
# 返回：worktree数量
worktree_count_total() {
    local project_root="${1:-$(pwd)}"
    
    worktree_list_all "$project_root" | wc -l
}

# 计算Epic worktree数量
# 参数：(optional: project_root)
# 返回：Epic worktree数量
worktree_count_epics() {
    local project_root="${1:-$(pwd)}"
    
    worktree_list_epics "$project_root" | wc -l
}

# 计算Feature worktree数量
# 参数：(optional: project_root)
# 返回：Feature worktree数量
worktree_count_features() {
    local project_root="${1:-$(pwd)}"
    
    worktree_list_features "$project_root" | wc -l
}