#!/bin/bash
# NewGPF Core - Environment Detection Atomic Methods
# 环境检测原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 查找项目根目录
# 查找主Git仓库目录（包含.git目录，不是worktree的.git文件）
# 项目根目录 = 主Git仓库目录，Epic/Feature都在其下的.worktrees/中
# 返回：绝对路径字符串 或 返回码1（未找到主Git仓库）
find_project_root() {
    local current_dir
    current_dir=$(pwd)
    
    # 从当前目录向上查找主Git仓库
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            # 找到.git目录（主仓库），这是项目根目录
            echo "$current_dir"
            return 0
        elif [[ -f "$current_dir/.git" ]]; then
            # 找到.git文件（worktree），需要解析出主仓库位置
            local main_git_dir
            main_git_dir=$(extract_main_git_dir_from_worktree "$current_dir/.git")
            if [[ -n "$main_git_dir" ]]; then
                # 主仓库目录 = .git目录的父目录
                echo "$(dirname "$main_git_dir")"
                return 0
            fi
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    # 未找到Git仓库
    return 1
}

# 从worktree的.git文件中提取主仓库的.git目录路径
# 参数：(worktree_git_file_path)
# 返回：主仓库.git目录路径 或 空字符串
extract_main_git_dir_from_worktree() {
    local git_file="$1"
    
    if [[ ! -f "$git_file" ]]; then
        return 1
    fi
    
    # 读取.git文件内容，格式：gitdir: /path/to/main/.git/worktrees/branch
    local gitdir_line
    gitdir_line=$(head -1 "$git_file")
    
    # 提取gitdir路径
    local gitdir_path
    gitdir_path=$(echo "$gitdir_line" | sed 's/^gitdir:[[:space:]]*//')
    
    if [[ -n "$gitdir_path" ]]; then
        # 从 /main/.git/worktrees/branch 推导出 /main/.git
        local main_git_dir
        main_git_dir=$(echo "$gitdir_path" | sed 's|/worktrees/.*||')
        echo "$main_git_dir"
    fi
}

# 判断环境类型
# 参数：(current_path, project_root)
# 返回：root|epic|feature|unknown
determine_environment_type() {
    local current_path="$1"
    local project_root="$2"
    
    # 标准化路径，移除尾部斜杠
    current_path="${current_path%/}"
    project_root="${project_root%/}"
    
    # 检查是否在工作树中
    if [[ "$current_path" == "$project_root/.worktrees/"* ]]; then
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
# 参数：(current_path, project_root)
# 返回：JSON格式的Epic环境信息
extract_epic_environment() {
    local current_path="$1"
    local project_root="$2"
    
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
# 参数：(current_path, project_root)
# 返回：JSON格式的Feature环境信息
extract_feature_environment() {
    local current_path="$1"
    local project_root="$2"
    
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
# 参数：(current_path, project_root)
# 返回：JSON格式的根环境信息
extract_root_environment() {
    local current_path="$1"
    local project_root="$2"
    
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
# 参数：(current_path, project_root)
# 返回：JSON格式的未知环境信息
extract_unknown_environment() {
    local current_path="$1"
    local project_root="$2"
    
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