#!/bin/bash
# GPF Core - Environment Detection Composite Methods
# 环境检测组合方法 - 组合原子方法实现完整环境检测

set -euo pipefail

# 导入依赖的原子方法
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/environment-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/platform-utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/gh-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/git-atomic.sh"

# =============================================================================
# 🌟 Modules层专用接口 - 基础设施方法
# =============================================================================

# 获取项目根目录（供Modules层调用）
# 这是对atomic层find_project_root()的composite层包装，遵循逐层调用原则
# 参数：无
# 返回：项目根目录绝对路径
environment_get_project_root() {
    find_project_root
}

# =============================================================================
# 完整环境检测组合方法
# =============================================================================

# 完整环境检测
# 参数：无
# 返回：JSON格式的完整环境检测结果
environment_detect_complete() {
    # 获取平台信息
    local platform_name
    platform_name=$(detect_platform)
    
    # 获取GitHub CLI信息
    local gh_info
    gh_info=$(gh_get_status)
    
    # 检查项目根目录
    local project_root=""
    if project_root=$(find_project_root 2>/dev/null); then
        # 项目根目录存在
        :
    else
        project_root=""
    fi
    
    # 检查GPF工作目录
    local gpf_workspace=""
    if [[ -n "$project_root" && -d "$project_root/.worktrees" ]]; then
        gpf_workspace="$project_root/.worktrees"
    fi
    
    # 获取Git信息（如果在Git仓库中）
    local git_version=""
    local git_valid="false"
    local current_branch=""
    if command -v git >/dev/null 2>&1; then
        git_version=$(git --version 2>/dev/null | sed 's/git version //' || echo "unknown")
        if [[ -n "$project_root" ]]; then
            if git_check_repository_valid 2>/dev/null; then
                git_valid="true"
                current_branch=$(git_get_current_branch 2>/dev/null || echo "unknown")
            fi
        fi
    fi
    
    # 获取环境变量
    local shell_env="${SHELL:-unknown}"
    local home_dir="${HOME:-unknown}"
    local path_info="${PATH:-unknown}"
    
    # 获取环境类型
    local env_type="unknown"
    local env_info="{}"
    if [[ -n "$project_root" ]]; then
        env_type=$(determine_environment_type 2>/dev/null || echo "unknown")
        case "$env_type" in
            "epic")
                env_info=$(extract_epic_environment 2>/dev/null || echo "{}")
                ;;
            "feature")
                env_info=$(extract_feature_environment 2>/dev/null || echo "{}")
                ;;
            "root")
                env_info=$(extract_root_environment 2>/dev/null || echo "{}")
                ;;
            *)
                env_info=$(extract_unknown_environment 2>/dev/null || echo "{}")
                ;;
        esac
    fi
    
    # 合并所有信息
    cat << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "platform": {
        "name": "$platform_name",
        "path_separator": "$(get_path_separator)",
        "temp_directory": "$(get_temp_directory 2>/dev/null || echo "/tmp")",
        "home_directory": "$(get_home_directory 2>/dev/null || echo "$HOME")"
    },
    "git": {
        "version": "$git_version",
        "available": $(if command -v git >/dev/null 2>&1; then echo "true"; else echo "false"; fi),
        "repository_valid": $git_valid,
        "current_branch": "$current_branch"
    },
    "github": $gh_info,
    "project": {
        "root": "$project_root",
        "gpf_workspace": "$gpf_workspace",
        "is_gpf_project": $(if [[ -n "$gpf_workspace" ]]; then echo "true"; else echo "false"; fi)
    },
    "environment": {
        "type": "$env_type",
        "details": $env_info
    },
    "shell": {
        "type": "$shell_env",
        "home": "$home_dir",
        "path_configured": $(if [[ "$path_info" != "unknown" ]]; then echo "true"; else echo "false"; fi)
    },
    "capabilities": {
        "git_available": $(if command -v git >/dev/null 2>&1; then echo "true"; else echo "false"; fi),
        "gh_available": $(if command -v gh >/dev/null 2>&1; then echo "true"; else echo "false"; fi),
        "jq_available": $(if command -v jq >/dev/null 2>&1; then echo "true"; else echo "false"; fi),
        "curl_available": $(if command -v curl >/dev/null 2>&1; then echo "true"; else echo "false"; fi)
    },
    "compatibility": {
        "bash_version": "${BASH_VERSION:-unknown}",
        "bash_compatible": $(if [[ "${BASH_VERSION:-}" =~ ^[4-9] ]]; then echo "true"; else echo "false"; fi),
        "platform_supported": $(if [[ "$platform_name" =~ ^(linux|macos|windows)$ ]]; then echo "true"; else echo "false"; fi)
    }
}
EOF
}

# 检查环境兼容性
# 参数：无
# 返回：0（兼容）或1（不兼容）
environment_check_compatibility() {
    local detection_result
    detection_result=$(environment_detect_complete)
    
    # 检查必需的工具
    local git_available gh_available jq_available bash_compatible platform_supported
    git_available=$(echo "$detection_result" | jq -r '.capabilities.git_available')
    gh_available=$(echo "$detection_result" | jq -r '.capabilities.gh_available')
    jq_available=$(echo "$detection_result" | jq -r '.capabilities.jq_available')
    bash_compatible=$(echo "$detection_result" | jq -r '.compatibility.bash_compatible')
    platform_supported=$(echo "$detection_result" | jq -r '.compatibility.platform_supported')
    
    # 检查兼容性
    if [[ "$git_available" == "true" && "$jq_available" == "true" && "$bash_compatible" == "true" && "$platform_supported" == "true" ]]; then
        return 0  # 兼容
    else
        return 1  # 不兼容
    fi
}

# 获取环境问题报告
# 参数：无
# 返回：JSON格式的问题报告
environment_get_issues() {
    local detection_result
    detection_result=$(environment_detect_complete)
    
    local issues=()
    
    # 检查Git
    if [[ "$(echo "$detection_result" | jq -r '.capabilities.git_available')" == "false" ]]; then
        issues+=("Git not installed or not in PATH")
    fi
    
    # 检查jq
    if [[ "$(echo "$detection_result" | jq -r '.capabilities.jq_available')" == "false" ]]; then
        issues+=("jq not installed or not in PATH")
    fi
    
    # 检查Bash版本
    if [[ "$(echo "$detection_result" | jq -r '.compatibility.bash_compatible')" == "false" ]]; then
        issues+=("Bash version too old (4.0+ required)")
    fi
    
    # 检查平台支持
    if [[ "$(echo "$detection_result" | jq -r '.compatibility.platform_supported')" == "false" ]]; then
        issues+=("Platform not supported")
    fi
    
    # 检查GitHub CLI（警告级别）
    local warnings=()
    if [[ "$(echo "$detection_result" | jq -r '.capabilities.gh_available')" == "false" ]]; then
        warnings+=("GitHub CLI not installed (some features may be limited)")
    fi
    
    # 检查GitHub CLI认证
    if [[ "$(echo "$detection_result" | jq -r '.github.authenticated')" == "false" ]]; then
        warnings+=("GitHub CLI not authenticated (PR features unavailable)")
    fi
    
    # 构建问题数组JSON
    local issues_json="[]"
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)
    fi
    
    local warnings_json="[]"
    if [[ ${#warnings[@]} -gt 0 ]]; then
        warnings_json=$(printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .)
    fi
    
    cat << EOF
{
    "has_issues": $(if [[ ${#issues[@]} -gt 0 ]]; then echo "true"; else echo "false"; fi),
    "has_warnings": $(if [[ ${#warnings[@]} -gt 0 ]]; then echo "true"; else echo "false"; fi),
    "issues": $issues_json,
    "warnings": $warnings_json,
    "compatible": $(if [[ ${#issues[@]} -eq 0 ]]; then echo "true"; else echo "false"; fi)
}
EOF
}

# 获取环境摘要
# 参数：无
# 返回：简化的环境摘要信息
environment_get_summary() {
    local detection_result issues_result
    detection_result=$(environment_detect_complete)
    issues_result=$(environment_get_issues)
    
    local platform git_version gh_version is_gpf_project
    platform=$(echo "$detection_result" | jq -r '.platform.name')
    git_version=$(echo "$detection_result" | jq -r '.git.version // "not available"')
    gh_version=$(echo "$detection_result" | jq -r '.github.version // "not available"')
    is_gpf_project=$(echo "$detection_result" | jq -r '.project.is_gpf_project')
    
    cat << EOF
{
    "platform": "$platform",
    "git_version": "$git_version",
    "github_cli_version": "$gh_version",
    "is_gpf_project": $is_gpf_project,
    "compatible": $(echo "$issues_result" | jq -r '.compatible'),
    "issues_count": $(echo "$issues_result" | jq -r '.issues | length'),
    "warnings_count": $(echo "$issues_result" | jq -r '.warnings | length')
}
EOF
}