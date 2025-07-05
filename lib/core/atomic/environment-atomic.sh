#!/bin/bash
# GPF Core - Environment Detection Atomic Methods
# 环境检测原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 导入平台兼容性工具
source "$(dirname "${BASH_SOURCE[0]}")/platform-utils.sh"

# 查找项目根目录
# 从当前目录往上找.git，检查路径是否包含.worktree，如果包含则继续往上找
# 直到找到一个.git路径不包含.worktree的目录，那就是真正的根目录
# 这样可以处理嵌套worktree的情况，并支持跨平台兼容性
# 返回：绝对路径字符串 或 返回码1（未找到根Git仓库）
find_project_root() {
    local current_dir
    current_dir=$(get_absolute_path "$(pwd)")
    
    # 从当前目录向上查找Git仓库
    while ! is_root_path "$current_dir"; do
        # 检查是否存在.git（目录或文件）
        local git_dir
        local git_file
        git_dir=$(join_paths "$current_dir" ".git")
        git_file="$git_dir"
        
        if [[ -d "$git_dir" ]] || [[ -f "$git_file" ]]; then
            # 检查当前路径是否包含.worktree（表示在worktree中）
            if path_contains "$current_dir" ".worktree"; then
                # 在worktree中，继续往上找真正的根目录
                current_dir=$(get_parent_directory "$current_dir")
                continue
            else
                # 找到不包含.worktree的.git，这是项目根目录
                echo "$current_dir"
                return 0
            fi
        fi
        current_dir=$(get_parent_directory "$current_dir")
    done
    
    # 未找到Git仓库
    return 1
}

# 判断环境类型
# 参数：(current_path) - 可选，默认使用当前目录
# 返回：root|epic|feature|unknown
# 注意：内部使用find_project_root()获取标准根目录，确保一致性
determine_environment_type() {
    local current_path="${1:-$(pwd)}"
    
    # 使用标准方法获取项目根目录
    local project_root
    project_root=$(find_project_root) || {
        echo "unknown"
        return 1
    }
    
    # 标准化路径，移除尾部斜杠
    current_path="${current_path%/}"
    project_root="${project_root%/}"
    
    # 检查是否在工作树中
    local worktrees_path
    worktrees_path=$(join_paths "$project_root" ".worktrees")
    
    if path_starts_with "$current_path" "$worktrees_path"; then
        local worktree_name
        worktree_name=$(basename "$current_path")
        
        if [[ "$worktree_name" =~ -ef$ ]]; then
            echo "feature"
        elif [[ "$worktree_name" =~ -e$ ]]; then
            echo "epic"  
        else
            echo "unknown"
        fi
    elif [[ "$current_path" == "$project_root" ]]; then
        echo "root"
    else
        echo "unknown"
    fi
}

# 从工作树路径提取工作树名称
# 参数：(worktree_path, project_root)
# 返回：工作树名称
extract_worktree_name() {
    local worktree_path="$1"
    local project_root="$2"
    
    # 移除项目根目录和.worktrees/前缀
    local relative_path="${worktree_path#$project_root/.worktrees/}"
    echo "$relative_path"
}

# 提取Epic环境信息
# 参数：(current_path) - 可选，默认使用当前目录
# 返回：JSON格式的Epic环境信息
extract_epic_environment() {
    local current_path="${1:-$(pwd)}"
    
    # 使用标准方法获取项目根目录
    local project_root
    project_root=$(find_project_root) || return 1
    
    local worktree_name
    worktree_name=$(extract_worktree_name "$current_path" "$project_root")
    
    # 从Epic分支名提取Epic名称: epic-auth-e -> auth
    local epic_name="${worktree_name#epic-}"
    epic_name="${epic_name%-e}"
    
    local git_branch
    git_branch=$(git -C "$current_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    cat << EOF
{
    "type": "epic",
    "project_root": "$project_root",
    "current_path": "$current_path",
    "epic_name": "$epic_name",
    "feature_name": null,
    "git_branch": "$git_branch",
    "worktree_path": "$current_path"
}
EOF
}

# 提取Feature环境信息
# 参数：(current_path) - 可选，默认使用当前目录
# 返回：JSON格式的Feature环境信息
extract_feature_environment() {
    local current_path="${1:-$(pwd)}"
    
    # 使用标准方法获取项目根目录
    local project_root
    project_root=$(find_project_root) || return 1
    
    local worktree_name
    worktree_name=$(extract_worktree_name "$current_path" "$project_root")
    
    # 从Feature分支名提取信息: epic-auth-e-login-ef -> auth, login
    local clean_name="${worktree_name#epic-}"
    clean_name="${clean_name%-ef}"
    
    # 分割epic和feature部分: auth-e-login -> auth, login
    local epic_name="${clean_name%-e-*}"
    local feature_name="${clean_name#*-e-}"
    
    local git_branch
    git_branch=$(git -C "$current_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    cat << EOF
{
    "type": "feature",
    "project_root": "$project_root",
    "current_path": "$current_path",
    "epic_name": "$epic_name",
    "feature_name": "$feature_name",
    "git_branch": "$git_branch",
    "worktree_path": "$current_path"
}
EOF
}

# 提取根环境信息
# 参数：(current_path) - 可选，默认使用当前目录
# 返回：JSON格式的根环境信息
extract_root_environment() {
    local current_path="${1:-$(pwd)}"
    
    # 使用标准方法获取项目根目录
    local project_root
    project_root=$(find_project_root) || return 1
    
    local git_branch
    git_branch=$(git -C "$current_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    cat << EOF
{
    "type": "root",
    "project_root": "$project_root",
    "current_path": "$current_path",
    "epic_name": null,
    "feature_name": null,
    "git_branch": "$git_branch",
    "worktree_path": null
}
EOF
}

# 提取未知环境信息
# 参数：(current_path) - 可选，默认使用当前目录
# 返回：JSON格式的未知环境信息
extract_unknown_environment() {
    local current_path="${1:-$(pwd)}"
    
    # 使用标准方法获取项目根目录
    local project_root
    project_root=$(find_project_root) || return 1
    
    local git_branch
    git_branch=$(git -C "$current_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    cat << EOF
{
    "type": "unknown",
    "project_root": "$project_root",
    "current_path": "$current_path",
    "epic_name": null,
    "feature_name": null,
    "git_branch": "$git_branch",
    "worktree_path": null
}
EOF
}