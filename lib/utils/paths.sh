#!/usr/bin/env bash

# Git PR Flow - 路径管理工具
# 统一所有路径计算和目录操作，支持跨平台兼容

# 路径分隔符（跨平台兼容）
readonly GPF_GPF_PATH_SEP="/"
readonly GPF_GPF_WORKTREE_SEP="--"

# =====================================================
# 项目根目录相关
# =====================================================

# 获取项目根目录的绝对路径
get_project_root_path() {
    local current_dir=$(pwd)
    local project_root=""
    
    # 方法1: 从当前路径推断（优先处理worktree情况）
    if [[ "$current_dir" == *"/.worktrees/"* ]]; then
        # 在worktree中，推断项目根目录
        project_root=$(echo "$current_dir" | sed 's|/\.worktrees/.*||')
    else
        # 使用git获取根目录
        project_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
    fi
    
    # 验证项目根目录
    if [[ -n "$project_root" && -d "$project_root/.git" && -f "$project_root/bin/git-pr-flow" ]]; then
        echo "$project_root"
        return 0
    fi
    
    return 1
}

# 获取相对于项目根目录的绝对路径
resolve_project_path() {
    local relative_path="$1"
    local project_root
    
    project_root=$(get_project_root_path) || {
        echo "Error: Cannot determine project root" >&2
        return 1
    }
    
    echo "$project_root/$relative_path"
}

# 检查当前是否在项目根目录
is_in_project_root() {
    local current_dir=$(pwd)
    local project_root
    project_root=$(get_project_root_path) || return 1
    
    [[ "$current_dir" == "$project_root" ]]
}

# 检查当前是否在worktree目录中
is_in_worktree() {
    local current_dir=$(pwd)
    [[ "$current_dir" == *"/.worktrees/"* ]]
}

# =====================================================
# Epic路径相关
# =====================================================

# 从Epic名称生成工作树路径
get_epic_worktree_path() {
    local epic_name="$1"
    echo ".worktrees/epic${GPF_WORKTREE_SEP}$epic_name"
}

# 从Epic名称生成绝对工作树路径
get_epic_worktree_absolute_path() {
    local epic_name="$1"
    local relative_path
    relative_path=$(get_epic_worktree_path "$epic_name")
    resolve_project_path "$relative_path"
}

# 从Epic名称生成配置文件路径
get_epic_config_path() {
    local epic_name="$1"
    local worktree_path
    worktree_path=$(get_epic_worktree_path "$epic_name")
    echo "$worktree_path/.git-pr-flow.yaml"
}

# 从Epic名称生成绝对配置文件路径
get_epic_config_absolute_path() {
    local epic_name="$1"
    local relative_path
    relative_path=$(get_epic_config_path "$epic_name")
    resolve_project_path "$relative_path"
}

# 检查Epic工作树是否存在
epic_worktree_exists() {
    local epic_name="$1"
    local worktree_path
    worktree_path=$(get_epic_worktree_absolute_path "$epic_name")
    [[ -d "$worktree_path" ]]
}

# 检查Epic配置文件是否存在
epic_config_exists() {
    local epic_name="$1"
    local config_path
    config_path=$(get_epic_config_absolute_path "$epic_name")
    [[ -f "$config_path" ]]
}

# =====================================================
# 功能分支路径相关  
# =====================================================

# 从分支名生成工作树路径（通用：支持epic/xx和xx/yy格式）
get_branch_worktree_path() {
    local branch_name="$1"
    # 将 / 替换为 --
    local worktree_name="${branch_name//${GPF_PATH_SEP}/${GPF_WORKTREE_SEP}}"
    echo ".worktrees/$worktree_name"
}

# 从分支名生成绝对工作树路径
get_branch_worktree_absolute_path() {
    local branch_name="$1"
    local relative_path
    relative_path=$(get_branch_worktree_path "$branch_name")
    resolve_project_path "$relative_path"
}

# 从功能名称提取Epic名称
extract_epic_from_feature() {
    local feature_name="$1"
    
    # 处理 epic/xx/yy 格式
    if [[ "$feature_name" == epic/* ]]; then
        echo "$feature_name" | sed 's|^epic/\([^/]*\)/.*|\1|'
    # 处理 xx/yy 格式  
    elif [[ "$feature_name" == */* ]]; then
        echo "$feature_name" | sed 's|^\([^/]*\)/.*|\1|'
    else
        return 1
    fi
}

# 检查功能分支工作树是否存在
feature_worktree_exists() {
    local feature_name="$1"
    local worktree_path
    worktree_path=$(get_branch_worktree_absolute_path "$feature_name")
    [[ -d "$worktree_path" ]]
}

# =====================================================
# 智能目录切换
# =====================================================

# 智能切换到Epic工作目录
switch_to_epic_directory() {
    local epic_name="$1"
    local worktree_path
    
    worktree_path=$(get_epic_worktree_absolute_path "$epic_name")
    
    if [[ ! -d "$worktree_path" ]]; then
        echo "Error: Epic工作树不存在: $worktree_path" >&2
        return 1
    fi
    
    local current_dir=$(pwd)
    if [[ "$current_dir" != "$worktree_path" ]]; then
        echo "Info: 切换到Epic工作目录: $epic_name" >&2
        echo "Info: 从: $current_dir" >&2  
        echo "Info: 到: $worktree_path" >&2
        cd "$worktree_path" || {
            echo "Error: 无法切换到Epic目录: $worktree_path" >&2
            return 1
        }
        echo "Success: 已切换到Epic工作目录" >&2
    fi
    
    return 0
}

# 智能切换到项目根目录
switch_to_project_root() {
    local project_root
    project_root=$(get_project_root_path) || {
        echo "Error: 无法确定项目根目录" >&2
        return 1
    }
    
    local current_dir=$(pwd)
    if [[ "$current_dir" != "$project_root" ]]; then
        echo "Info: 切换到项目根目录" >&2
        echo "Info: 从: $current_dir" >&2
        echo "Info: 到: $project_root" >&2
        cd "$project_root" || {
            echo "Error: 无法切换到项目根目录: $project_root" >&2
            return 1
        }
        echo "Success: 已切换到项目根目录" >&2
    fi
    
    return 0
}

# 根据功能名称智能切换到对应Epic目录
smart_switch_to_epic_for_feature() {
    local feature_name="$1"
    local epic_name
    
    epic_name=$(extract_epic_from_feature "$feature_name") || {
        echo "Error: 无法从功能名称提取Epic: $feature_name" >&2
        return 1
    }
    
    switch_to_epic_directory "$epic_name"
}

# =====================================================
# 路径验证和规范化
# =====================================================

# 验证Epic名称格式
validate_epic_name() {
    local epic_name="$1"
    
    # 基本检查
    if [[ -z "$epic_name" ]]; then
        return 1
    fi
    
    # 长度检查 (3-50字符)
    if [[ ${#epic_name} -lt 3 || ${#epic_name} -gt 50 ]]; then
        return 1
    fi
    
    # 格式检查: 只允许小写字母、数字、连字符
    if [[ ! "$epic_name" =~ ^[a-z0-9-]+$ ]]; then
        return 1
    fi
    
    # 不能以连字符开头或结尾
    if [[ "$epic_name" =~ ^- ]] || [[ "$epic_name" =~ -$ ]]; then
        return 1
    fi
    
    # 不能包含连续的连字符
    if [[ "$epic_name" =~ -- ]]; then
        return 1
    fi
    
    return 0
}

# 规范化Epic名称（去除epic/前缀）
normalize_epic_name() {
    local epic_name="$1"
    echo "${epic_name#epic/}"
}

# 规范化分支名称到Epic格式（添加epic/前缀）
to_epic_branch_name() {
    local epic_name="$1"
    epic_name=$(normalize_epic_name "$epic_name")
    echo "epic/$epic_name"
}

# =====================================================
# 工具函数
# =====================================================

# 列出所有Epic工作树
list_epic_worktrees() {
    local project_root
    project_root=$(get_project_root_path) || return 1
    
    if [[ -d "$project_root/.worktrees" ]]; then
        find "$project_root/.worktrees" -maxdepth 1 -type d -name "epic--*" | while read -r dir; do
            local worktree_name
            worktree_name=$(basename "$dir")
            local epic_name="${worktree_name#epic--}"
            echo "$epic_name"
        done
    fi
}

# 列出所有功能工作树（非Epic）
list_feature_worktrees() {
    local project_root
    project_root=$(get_project_root_path) || return 1
    
    if [[ -d "$project_root/.worktrees" ]]; then
        find "$project_root/.worktrees" -maxdepth 1 -type d ! -name "epic--*" -name "*--*" | while read -r dir; do
            local worktree_name
            worktree_name=$(basename "$dir")
            # 将 -- 转换回 /
            local feature_name="${worktree_name//${GPF_WORKTREE_SEP}/${GPF_PATH_SEP}}"
            echo "$feature_name"
        done
    fi
}

# 清理空的或无效的工作树目录
cleanup_invalid_worktrees() {
    local project_root
    project_root=$(get_project_root_path) || return 1
    
    if [[ -d "$project_root/.worktrees" ]]; then
        find "$project_root/.worktrees" -maxdepth 1 -type d -empty -delete 2>/dev/null || true
    fi
}