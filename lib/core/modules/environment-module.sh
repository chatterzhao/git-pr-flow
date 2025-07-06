#!/bin/bash
# GPF 环境管理模块 - 提供完整的环境检测、切换和兼容性验证
# 本模块为所有命令提供统一的环境管理服务

set -euo pipefail

# 按四层架构获取项目根目录（通过composite层）
# 临时加载environment-composite以获取项目根目录
source "$(dirname "${BASH_SOURCE[0]}")/../composite/environment-composite.sh"

# 通过composite层获取项目根目录（遵循四层架构）
PROJECT_ROOT=$(environment_get_project_root) || {
    echo "❌ 错误：无法通过composite层获取项目根目录" >&2
    exit 1
}

# 加载其他依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/git-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/path-composite.sh"

# ==============================================================================
# 环境管理模块 - 核心方法
# ==============================================================================

# 获取完整的环境信息（所有命令都会使用）
environment_module_get_complete_info() {
    local include_github="${1:-true}"     # 是否包含GitHub信息
    local include_project="${2:-true}"    # 是否包含项目信息
    local validation_level="${3:-basic}"  # basic/full/strict
    
    # 获取基础环境信息
    local base_environment
    base_environment=$(environment_detect_complete) || {
        echo "❌ 错误：无法检测环境" >&2
        return 1
    }
    
    # 获取详细环境信息
    local detailed_info
    detailed_info=$(environment_module_analyze_current_environment "$base_environment") || return 1
    
    # 获取GitHub环境信息（如果需要）
    local github_info="{}"
    if [[ "$include_github" == "true" ]]; then
        github_info=$(environment_module_get_github_environment) || github_info="{\"available\": false}"
    fi
    
    # 获取项目信息（如果需要）
    local project_info="{}"
    if [[ "$include_project" == "true" ]]; then
        project_info=$(environment_module_get_project_info) || project_info="{\"valid\": false}"
    fi
    
    # 执行环境验证（根据级别）
    local validation_result
    validation_result=$(environment_module_validate_environment "$validation_level") || return 1
    
    # 组合完整环境信息
    cat <<EOF
{
    "base_environment": "$base_environment",
    "detailed_info": $detailed_info,
    "github_info": $github_info,
    "project_info": $project_info,
    "validation_result": $validation_result,
    "timestamp": "$(date -u +"%Y-%m-%d %H:%M:%S")"
}
EOF
}

# 智能环境切换（start/clean/sync命令使用）
environment_module_intelligent_switch() {
    local target_environment="$1"       # root/epic/feature
    local target_name="${2:-}"          # Epic名称或Feature名称
    local base_branch="${3:-develop}"   # 基础分支
    local switch_mode="${4:-auto}"      # auto/force/validate
    
    # 获取当前环境
    local current_env
    current_env=$(environment_detect_complete) || {
        echo "❌ 错误：无法检测当前环境" >&2
        return 1
    }
    
    # 验证切换请求
    if ! environment_module_validate_switch_request "$current_env" "$target_environment" "$target_name" "$switch_mode"; then
        echo "❌ 错误：环境切换请求验证失败" >&2
        return 1
    fi
    
    # 执行环境切换
    case "$target_environment" in
        "root")
            environment_module_switch_to_root "$base_branch"
            ;;
        "epic")
            environment_module_switch_to_epic "$target_name" "$base_branch"
            ;;
        "feature")
            environment_module_switch_to_feature "$target_name" "$base_branch"
            ;;
        *)
            echo "❌ 错误：未知的目标环境: $target_environment" >&2
            return 1
            ;;
    esac
}

# 环境兼容性验证（所有命令启动时调用）
environment_module_compatibility_check() {
    local required_features="$1"        # JSON数组：["git", "github", "worktree"]
    local strict_mode="${2:-false}"     # 是否严格模式
    
    local compatibility_result="{\"compatible\": true, \"issues\": [], \"warnings\": []}"
    
    # 解析所需特性
    local features
    features=$(echo "$required_features" | jq -r '.[]' 2>/dev/null || echo "")
    
    # 检查每个特性
    while IFS= read -r feature; do
        [[ -n "$feature" ]] || continue
        
        case "$feature" in
            "git")
                if ! environment_module_check_git_compatibility; then
                    if [[ "$strict_mode" == "true" ]]; then
                        compatibility_result=$(echo "$compatibility_result" | jq '.compatible = false | .issues += ["Git兼容性检查失败"]')
                    else
                        compatibility_result=$(echo "$compatibility_result" | jq '.warnings += ["Git版本可能不兼容"]')
                    fi
                fi
                ;;
            "github")
                if ! environment_module_check_github_compatibility; then
                    if [[ "$strict_mode" == "true" ]]; then
                        compatibility_result=$(echo "$compatibility_result" | jq '.compatible = false | .issues += ["GitHub环境不可用"]')
                    else
                        compatibility_result=$(echo "$compatibility_result" | jq '.warnings += ["GitHub功能可能受限"]')
                    fi
                fi
                ;;
            "worktree")
                if ! environment_module_check_worktree_compatibility; then
                    if [[ "$strict_mode" == "true" ]]; then
                        compatibility_result=$(echo "$compatibility_result" | jq '.compatible = false | .issues += ["Worktree功能不可用"]')
                    else
                        compatibility_result=$(echo "$compatibility_result" | jq '.warnings += ["Worktree功能可能有问题"]')
                    fi
                fi
                ;;
            *)
                compatibility_result=$(echo "$compatibility_result" | jq --arg feature "$feature" '.warnings += ["未知特性: " + $feature]')
                ;;
        esac
    done <<< "$features"
    
    echo "$compatibility_result"
}

# ==============================================================================
# 环境分析和检测
# ==============================================================================

# 分析当前环境
environment_module_analyze_current_environment() {
    local base_environment="$1"
    
    local current_path=$(pwd)
    local project_root
    project_root=$(find_project_root) || {
        echo "❌ 错误：无法找到项目根目录" >&2
        return 1
    }
    
    case "$base_environment" in
        "root")
            environment_module_analyze_root_environment "$current_path" "$project_root"
            ;;
        "epic")
            environment_module_analyze_epic_environment "$current_path" "$project_root"
            ;;
        "feature")
            environment_module_analyze_feature_environment "$current_path" "$project_root"
            ;;
        *)
            environment_module_analyze_unknown_environment "$current_path" "$project_root"
            ;;
    esac
}

# 分析根环境
environment_module_analyze_root_environment() {
    local current_path="$1"
    local project_root="$2"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    local git_status
    git_status=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' \n')
    
    cat <<EOF
{
    "environment_type": "root",
    "current_path": "$current_path",
    "project_root": "$project_root",
    "current_branch": "$current_branch",
    "has_changes": $([ "$git_status" -gt 0 ] && echo "true" || echo "false"),
    "epic_name": null,
    "feature_name": null
}
EOF
}

# 分析Epic环境
environment_module_analyze_epic_environment() {
    local current_path="$1"
    local project_root="$2"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    local epic_name
    epic_name=$(extract_epic_from_branch "$current_branch" 2>/dev/null || echo "unknown")
    
    local git_status
    git_status=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' \n')
    
    # 检查是否有关联的Feature分支
    local related_features
    related_features=$(environment_module_find_related_features "$epic_name") || related_features="[]"
    
    cat <<EOF
{
    "environment_type": "epic",
    "current_path": "$current_path",
    "project_root": "$project_root",
    "current_branch": "$current_branch",
    "has_changes": $([ "$git_status" -gt 0 ] && echo "true" || echo "false"),
    "epic_name": "$epic_name",
    "feature_name": null,
    "related_features": $related_features
}
EOF
}

# 分析Feature环境
environment_module_analyze_feature_environment() {
    local current_path="$1"
    local project_root="$2"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    local epic_name
    epic_name=$(extract_epic_from_branch "$current_branch" 2>/dev/null || echo "unknown")
    
    local feature_name
    feature_name=$(extract_feature_name_from_branch "$current_branch" 2>/dev/null || echo "unknown")
    
    local git_status
    git_status=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' \n')
    
    # 检查Epic分支状态
    local epic_branch="epic-$epic_name-e"
    local epic_status
    epic_status=$(environment_module_check_epic_branch_status "$epic_branch") || epic_status="{\"exists\": false}"
    
    cat <<EOF
{
    "environment_type": "feature",
    "current_path": "$current_path",
    "project_root": "$project_root",
    "current_branch": "$current_branch",
    "has_changes": $([ "$git_status" -gt 0 ] && echo "true" || echo "false"),
    "epic_name": "$epic_name",
    "feature_name": "$feature_name",
    "epic_status": $epic_status
}
EOF
}

# 分析未知环境
environment_module_analyze_unknown_environment() {
    local current_path="$1"
    local project_root="$2"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    cat <<EOF
{
    "environment_type": "unknown",
    "current_path": "$current_path",
    "project_root": "$project_root",
    "current_branch": "$current_branch",
    "has_changes": false,
    "epic_name": null,
    "feature_name": null,
    "analysis": "无法识别的环境类型"
}
EOF
}

# ==============================================================================
# GitHub和项目环境检测
# ==============================================================================

# 获取GitHub环境信息
environment_module_get_github_environment() {
    # 检查GitHub CLI
    local gh_available="false"
    local gh_authenticated="false"
    local gh_connected="false"
    
    if gh_check_installation; then
        gh_available="true"
        
        if gh_check_auth; then
            gh_authenticated="true"
            
            if gh_check_connectivity; then
                gh_connected="true"
            fi
        fi
    fi
    
    # 获取仓库信息
    local repo_info="{}"
    if [[ "$gh_available" == "true" ]]; then
        local origin_url
        origin_url=$(git remote get-url origin 2>/dev/null || echo "")
        
        if [[ "$origin_url" =~ github\.com ]]; then
            repo_info=$(cat <<EOF
{
    "is_github_repo": true,
    "origin_url": "$origin_url",
    "repo_type": "github"
}
EOF
            )
        else
            repo_info='{"is_github_repo": false, "origin_url": "", "repo_type": "other"}'
        fi
    fi
    
    cat <<EOF
{
    "available": $gh_available,
    "authenticated": $gh_authenticated,
    "connected": $gh_connected,
    "repo_info": $repo_info
}
EOF
}

# 获取项目信息
environment_module_get_project_info() {
    local project_root
    project_root=$(find_project_root 2>/dev/null || echo "")
    
    if [[ -z "$project_root" ]]; then
        echo '{"valid": false, "reason": "未找到项目根目录"}'
        return 1
    fi
    
    # 检查GPF特征文件
    local gpf_executable="$project_root/bin/git-pr-flow"
    local gpf_version="unknown"
    
    if [[ -f "$gpf_executable" ]]; then
        gpf_version=$("$gpf_executable" --version 2>/dev/null | head -1 || echo "unknown")
    fi
    
    # 检查worktree目录
    local worktree_dir="$project_root/.worktrees"
    local worktree_count=0
    
    if [[ -d "$worktree_dir" ]]; then
        worktree_count=$(find "$worktree_dir" -maxdepth 1 -type d -name "epic-*" | wc -l | tr -d ' \n')
    fi
    
    # 检查配置文件
    local config_files=()
    [[ -f "$project_root/.gitignore" ]] && config_files+=(".gitignore")
    [[ -f "$project_root/README.md" ]] && config_files+=("README.md")
    [[ -f "$project_root/package.json" ]] && config_files+=("package.json")
    
    cat <<EOF
{
    "valid": true,
    "project_root": "$project_root",
    "gpf_version": "$gpf_version",
    "worktree_count": $worktree_count,
    "config_files": [$(printf '"%s",' "${config_files[@]}" | sed 's/,$//')],
    "gpf_executable": "$gpf_executable"
}
EOF
}

# ==============================================================================
# 环境验证
# ==============================================================================

# 验证环境
environment_module_validate_environment() {
    local validation_level="${1:-basic}"
    
    local validation_results="{\"valid\": true, \"issues\": [], \"warnings\": []}"
    
    case "$validation_level" in
        "basic")
            validation_results=$(environment_module_basic_validation)
            ;;
        "full")
            validation_results=$(environment_module_full_validation)
            ;;
        "strict")
            validation_results=$(environment_module_strict_validation)
            ;;
        *)
            echo "❌ 错误：未知的验证级别: $validation_level" >&2
            return 1
            ;;
    esac
    
    echo "$validation_results"
}

# 基础验证
environment_module_basic_validation() {
    local results="{\"valid\": true, \"issues\": [], \"warnings\": []}"
    
    # 检查Git
    if ! command -v git >/dev/null 2>&1; then
        results=$(echo "$results" | jq '.valid = false | .issues += ["Git未安装"]')
    fi
    
    # 检查项目根目录
    if ! find_project_root >/dev/null 2>&1; then
        results=$(echo "$results" | jq '.valid = false | .issues += ["不在GPF项目目录中"]')
    fi
    
    echo "$results"
}

# 完整验证
environment_module_full_validation() {
    local results
    results=$(environment_module_basic_validation)
    
    # 检查Git版本
    if command -v git >/dev/null 2>&1; then
        local git_version
        git_version=$(git --version | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        
        if ! version_compare "$git_version" "2.22" ">="; then
            results=$(echo "$results" | jq '.warnings += ["Git版本可能过低，推荐2.22+"]')
        fi
    fi
    
    # 检查GitHub CLI
    if ! gh_check_installation; then
        results=$(echo "$results" | jq '.warnings += ["GitHub CLI未安装，GitHub功能将不可用"]')
    fi
    
    # 检查worktree支持
    if command -v git >/dev/null 2>&1; then
        if ! git worktree list >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.warnings += ["Git worktree功能可能不可用"]')
        fi
    fi
    
    echo "$results"
}

# 严格验证
environment_module_strict_validation() {
    local results
    results=$(environment_module_full_validation)
    
    # 将警告升级为错误
    local warnings
    warnings=$(echo "$results" | jq -r '.warnings[]' 2>/dev/null || echo "")
    
    if [[ -n "$warnings" ]]; then
        while IFS= read -r warning; do
            [[ -n "$warning" ]] || continue
            results=$(echo "$results" | jq --arg warning "$warning" '.valid = false | .issues += [$warning]')
        done <<< "$warnings"
        
        results=$(echo "$results" | jq '.warnings = []')
    fi
    
    echo "$results"
}

# ==============================================================================
# 兼容性检查
# ==============================================================================

# 检查Git兼容性
environment_module_check_git_compatibility() {
    # 检查Git是否安装
    command -v git >/dev/null 2>&1 || return 1
    
    # 检查Git版本
    local git_version
    git_version=$(git --version | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    version_compare "$git_version" "2.22" ">=" || return 1
    
    # 检查worktree支持
    git worktree list >/dev/null 2>&1 || return 1
    
    return 0
}

# 检查GitHub兼容性
environment_module_check_github_compatibility() {
    # 检查GitHub CLI
    gh_check_installation || return 1
    gh_check_auth || return 1
    gh_check_connectivity || return 1
    
    return 0
}

# 检查Worktree兼容性
environment_module_check_worktree_compatibility() {
    # 检查Git worktree支持
    command -v git >/dev/null 2>&1 || return 1
    git worktree list >/dev/null 2>&1 || return 1
    
    # 检查worktree目录权限
    local project_root
    project_root=$(find_project_root) || return 1
    
    local worktree_dir="$project_root/.worktrees"
    if [[ -d "$worktree_dir" ]]; then
        [[ -w "$worktree_dir" ]] || return 1
    else
        [[ -w "$project_root" ]] || return 1
    fi
    
    return 0
}

# ==============================================================================
# 环境切换实现
# ==============================================================================

# 验证切换请求
environment_module_validate_switch_request() {
    local current_env="$1"
    local target_environment="$2"
    local target_name="$3"
    local switch_mode="$4"
    
    # 基础验证
    case "$target_environment" in
        "root")
            # 切换到根目录不需要特殊验证
            return 0
            ;;
        "epic")
            [[ -n "$target_name" ]] || {
                echo "❌ 错误：Epic切换需要指定Epic名称" >&2
                return 1
            }
            ;;
        "feature")
            [[ -n "$target_name" ]] || {
                echo "❌ 错误：Feature切换需要指定Feature名称" >&2
                return 1
            }
            
            # Feature切换需要Epic环境
            if [[ "$current_env" != "epic" && "$current_env" != "feature" ]]; then
                echo "❌ 错误：Feature切换需要在Epic或Feature环境中" >&2
                return 1
            fi
            ;;
    esac
    
    return 0
}

# 切换到根环境
environment_module_switch_to_root() {
    local base_branch="${1:-develop}"
    
    local project_root
    project_root=$(find_project_root) || return 1
    
    cd "$project_root" || return 1
    
    # 切换到指定分支
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    if [[ "$current_branch" != "$base_branch" ]]; then
        git checkout "$base_branch" >/dev/null 2>&1 || {
            echo "❌ 错误：无法切换到分支: $base_branch" >&2
            return 1
        }
    fi
    
    echo "✅ 已切换到根环境 (分支: $base_branch)"
    return 0
}

# 切换到Epic环境
environment_module_switch_to_epic() {
    local epic_name="$1"
    local base_branch="${2:-develop}"
    
    local epic_branch="epic-$epic_name-e"
    local worktree_path="$PROJECT_ROOT/.worktrees/$epic_branch"
    
    # 检查Epic worktree是否存在
    if [[ -d "$worktree_path" ]]; then
        cd "$worktree_path" || return 1
        echo "✅ 已切换到Epic环境: $epic_name"
    else
        echo "❌ 错误：Epic工作树不存在: $epic_branch" >&2
        return 1
    fi
    
    return 0
}

# 切换到Feature环境
environment_module_switch_to_feature() {
    local feature_name="$1"
    local base_branch="${2:-}"
    
    # 获取当前Epic名称
    local current_epic
    current_epic=$(extract_current_epic_name 2>/dev/null) || {
        echo "❌ 错误：无法确定当前Epic环境" >&2
        return 1
    }
    
    local feature_branch="epic-$current_epic-e-$feature_name-ef"
    local worktree_path="$PROJECT_ROOT/.worktrees/$feature_branch"
    
    # 检查Feature worktree是否存在
    if [[ -d "$worktree_path" ]]; then
        cd "$worktree_path" || return 1
        echo "✅ 已切换到Feature环境: $feature_name (Epic: $current_epic)"
    else
        echo "❌ 错误：Feature工作树不存在: $feature_branch" >&2
        return 1
    fi
    
    return 0
}

# ==============================================================================
# 辅助功能
# ==============================================================================

# 查找相关Feature
environment_module_find_related_features() {
    local epic_name="$1"
    
    local worktree_base="$PROJECT_ROOT/.worktrees"
    [[ -d "$worktree_base" ]] || {
        echo "[]"
        return 0
    }
    
    local features="[]"
    
    find "$worktree_base" -maxdepth 1 -type d -name "epic-$epic_name-e-*-ef" 2>/dev/null | while read -r feature_dir; do
        local feature_branch=$(basename "$feature_dir")
        local feature_name="${feature_branch#epic-$epic_name-e-}"
        feature_name="${feature_name%-ef}"
        
        features=$(echo "$features" | jq --arg name "$feature_name" --arg branch "$feature_branch" '. += [{name: $name, branch: $branch}]')
    done
    
    echo "$features"
}

# 检查Epic分支状态
environment_module_check_epic_branch_status() {
    local epic_branch="$1"
    local worktree_path="$PROJECT_ROOT/.worktrees/$epic_branch"
    
    if [[ -d "$worktree_path" ]]; then
        local has_changes="false"
        if ! git -C "$worktree_path" diff --quiet 2>/dev/null || \
           ! git -C "$worktree_path" diff --cached --quiet 2>/dev/null; then
            has_changes="true"
        fi
        
        cat <<EOF
{
    "exists": true,
    "worktree_path": "$worktree_path",
    "has_changes": $has_changes
}
EOF
    else
        echo '{"exists": false}'
    fi
}

# 版本比较
version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="$3"
    
    # 简单的版本比较实现
    local v1_major v1_minor v2_major v2_minor
    v1_major="${version1%%.*}"
    v1_minor="${version1#*.}"
    v2_major="${version2%%.*}"
    v2_minor="${version2#*.}"
    
    case "$operator" in
        ">=")
            [[ "$v1_major" -gt "$v2_major" ]] || \
            [[ "$v1_major" -eq "$v2_major" && "$v1_minor" -ge "$v2_minor" ]]
            ;;
        *)
            return 1
            ;;
    esac
}