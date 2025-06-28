#!/usr/bin/env bash

# Git PR Flow - 智能推送工具
# 解决不同用户Git配置环境下的推送兼容性问题

# 引入依赖 (检查是否已加载，避免重复)
if [[ -z "${GPF_UI_LOADED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
fi
if [[ -z "${GPF_PATHS_LOADED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
fi

# =====================================================
# 远程仓库检测和管理
# =====================================================

# 检测所有可用的远程仓库
detect_available_remotes() {
    local remotes=()
    local all_remotes
    
    # 获取所有配置的远程
    all_remotes=($(git remote 2>/dev/null || echo ""))
    
    if [[ ${#all_remotes[@]} -eq 0 ]]; then
        log_debug "没有配置远程仓库"
        return 1
    fi
    
    # 按优先级排序
    local preferred_order=("origin" "upstream" "github" "gitee" "gitlab" "all")
    
    # 首先添加优先级高的远程
    for remote in "${preferred_order[@]}"; do
        if [[ " ${all_remotes[*]} " == *" $remote "* ]]; then
            remotes+=("$remote")
        fi
    done
    
    # 然后添加其他远程
    for remote in "${all_remotes[@]}"; do
        if [[ ! " ${remotes[*]} " == *" $remote "* ]]; then
            remotes+=("$remote")
        fi
    done
    
    echo "${remotes[@]}"
}

# 测试远程仓库的连接性和权限
test_remote_connectivity() {
    local remote="$1"
    local timeout="${2:-10}"
    
    if [[ -z "$remote" ]]; then
        return 1
    fi
    
    log_debug "测试远程仓库连接性: $remote"
    
    # 使用timeout避免长时间等待
    if timeout "$timeout" git ls-remote "$remote" HEAD >/dev/null 2>&1; then
        log_debug "远程仓库 $remote 连接成功"
        return 0
    else
        log_debug "远程仓库 $remote 连接失败"
        return 1
    fi
}

# 检测远程仓库的推送权限
test_remote_push_permission() {
    local remote="$1"
    local branch="${2:-$(git branch --show-current)}"
    
    if [[ -z "$remote" || -z "$branch" ]]; then
        return 1
    fi
    
    log_debug "测试远程仓库推送权限: $remote/$branch"
    
    # 使用dry-run测试推送权限，不实际推送
    if git push --dry-run "$remote" "$branch" >/dev/null 2>&1; then
        log_debug "远程仓库 $remote 推送权限验证成功"
        return 0
    else
        log_debug "远程仓库 $remote 推送权限验证失败"
        return 1
    fi
}

# 获取分支的upstream配置
get_branch_upstream() {
    local branch="${1:-$(git branch --show-current)}"
    
    if [[ -z "$branch" ]]; then
        return 1
    fi
    
    local upstream_remote upstream_branch
    upstream_remote=$(git config "branch.$branch.remote" 2>/dev/null || echo "")
    upstream_branch=$(git config "branch.$branch.merge" 2>/dev/null | sed 's|refs/heads/||' || echo "")
    
    if [[ -n "$upstream_remote" && -n "$upstream_branch" ]]; then
        echo "$upstream_remote/$upstream_branch"
        return 0
    fi
    
    return 1
}

# 检测代码托管平台远程（排除本地和非托管平台远程）
detect_hosting_platform_remotes() {
    local all_remotes
    all_remotes=($(git remote 2>/dev/null || echo ""))
    
    local platform_remotes=()
    
    for remote in "${all_remotes[@]}"; do
        local remote_url
        remote_url=$(git config "remote.$remote.url" 2>/dev/null || echo "")
        
        # 检测是否是代码托管平台（基于URL模式）
        if [[ "$remote_url" =~ (github\.com|gitee\.com|gitlab\.com|bitbucket\.org|codeberg\.org|gitea\.|gogs\.) ]]; then
            # 验证是否可推送
            if git push --dry-run "$remote" HEAD >/dev/null 2>&1; then
                platform_remotes+=("$remote")
            fi
        elif [[ "$remote" != "origin" && "$remote" != "upstream" ]]; then
            # 对于非标准命名的远程，也检查是否可推送（可能是自建Git服务）
            if git push --dry-run "$remote" HEAD >/dev/null 2>&1; then
                # 简单启发式：如果不是origin/upstream，且可推送，可能是托管平台
                platform_remotes+=("$remote")
            fi
        fi
    done
    
    echo "${platform_remotes[@]}"
}

# =====================================================
# 智能推送策略
# =====================================================

# 智能选择推送目标（基于用户的Git配置模式）
smart_select_push_target() {
    local branch="${1:-$(git branch --show-current)}"
    local force_mode="${2:-false}"
    
    if [[ -z "$branch" ]]; then
        ui_error "无法确定当前分支"
        return 1
    fi
    
    log_debug "为分支 $branch 选择推送目标"
    
    # 获取所有远程
    local all_remotes
    all_remotes=($(git remote 2>/dev/null || echo ""))
    
    if [[ ${#all_remotes[@]} -eq 0 ]]; then
        ui_error "没有配置远程仓库"
        return 1
    fi
    
    # 1. 首先检查是否有多平台配置，多平台优先于单平台upstream
    # 检查是否有配置多个pushurl的远程（如all）
    for remote in "${all_remotes[@]}"; do
        local pushurl_count
        pushurl_count=$(git config --get-all "remote.$remote.pushurl" 2>/dev/null | wc -l | tr -d ' ')
        
        if [[ "$pushurl_count" -gt 1 ]]; then
            # 验证多平台远程是否可用
            if git push --dry-run "$remote" "$branch" >/dev/null 2>&1; then
                log_debug "优先选择多平台远程: $remote (推送到 $pushurl_count 个平台)"
                echo "$remote"
                return 0
            fi
        fi
    done
    
    # 2. 如果没有多平台配置，则使用已配置的upstream
    local upstream
    upstream=$(get_branch_upstream "$branch")
    if [[ -n "$upstream" ]]; then
        local upstream_remote="${upstream%/*}"
        log_debug "使用已配置的upstream: $upstream"
        echo "$upstream_remote"
        return 0
    fi
    
    # 3. 标准配置检测：如果只有origin，直接使用
    if [[ ${#all_remotes[@]} -eq 1 && "${all_remotes[0]}" == "origin" ]]; then
        log_debug "检测到标准Git配置，使用origin"
        echo "origin"
        return 0
    fi
    
    # 标准优先级顺序：origin > github > gitee > 其他
    local priority_remotes=("origin" "github" "gitee")
    
    for remote in "${priority_remotes[@]}"; do
        if [[ " ${all_remotes[*]} " == *" $remote "* ]]; then
            # 使用dry-run快速验证是否可推送
            if git push --dry-run "$remote" "$branch" >/dev/null 2>&1; then
                log_debug "选择远程: $remote (通过dry-run验证)"
                echo "$remote"
                return 0
            fi
        fi
    done
    
    # 5. 如果优先级远程都不可用，测试其他远程
    for remote in "${all_remotes[@]}"; do
        if [[ ! " ${priority_remotes[*]} " == *" $remote "* ]]; then
            if git push --dry-run "$remote" "$branch" >/dev/null 2>&1; then
                log_debug "选择远程: $remote (其他可用远程)"
                echo "$remote"
                return 0
            fi
        fi
    done
    
    # 6. 如果都失败，返回第一个可用的远程（用户可能需要手动处理认证）
    log_debug "无法验证推送权限，返回第一个远程: ${all_remotes[0]}"
    echo "${all_remotes[0]}"
    return 0
}

# 执行智能推送
smart_push_branch() {
    local branch="${1:-$(git branch --show-current)}"
    local force="${2:-false}"
    local set_upstream="${3:-true}"
    
    if [[ -z "$branch" ]]; then
        ui_error "无法确定当前分支"
        return 1
    fi
    
    ui_loading "准备推送分支: $branch"
    
    # 选择推送目标
    local remote
    remote=$(smart_select_push_target "$branch" "$force")
    
    if [[ -z "$remote" ]]; then
        ui_error "无法确定推送目标"
        return 1
    fi
    
    # 构建推送命令
    local push_cmd="git push"
    
    if [[ "$force" == "true" ]]; then
        push_cmd="$push_cmd --force-with-lease"
        ui_warning "使用强制推送模式"
    fi
    
    if [[ "$set_upstream" == "true" ]]; then
        push_cmd="$push_cmd --set-upstream"
    fi
    
    push_cmd="$push_cmd $remote $branch"
    
    ui_info "执行推送: $push_cmd"
    
    # 执行推送
    if eval "$push_cmd"; then
        ui_success "分支推送成功: $branch → $remote"
        
        # 缓存成功的推送配置
        cache_successful_push_config "$branch" "$remote"
        
        return 0
    else
        ui_error "分支推送失败: $branch → $remote"
        return 1
    fi
}

# =====================================================
# 配置缓存和管理
# =====================================================

# 缓存成功的推送配置
cache_successful_push_config() {
    local branch="$1"
    local remote="$2"
    
    if [[ -z "$branch" || -z "$remote" ]]; then
        return 1
    fi
    
    log_debug "缓存推送配置: $branch → $remote"
    
    # 保存到Epic配置中
    local current_epic
    current_epic=$(detect_current_epic)
    
    if [[ -n "$current_epic" ]]; then
        config_epic_set "push.last_successful_remote" "$remote" "$current_epic"
        config_epic_set "push.last_successful_branch" "$branch" "$current_epic"
        config_epic_set "push.last_success_time" "$(date '+%Y-%m-%d %H:%M:%S')" "$current_epic"
    fi
    
    return 0
}

# 获取缓存的推送配置
get_cached_push_config() {
    local branch="$1"
    
    local current_epic
    current_epic=$(detect_current_epic)
    
    if [[ -n "$current_epic" ]]; then
        local cached_remote
        cached_remote=$(config_epic_get "push.last_successful_remote" "$current_epic")
        
        if [[ -n "$cached_remote" ]]; then
            echo "$cached_remote"
            return 0
        fi
    fi
    
    return 1
}

# =====================================================
# 推送诊断和帮助
# =====================================================

# 诊断推送问题
diagnose_push_issues() {
    local branch="${1:-$(git branch --show-current)}"
    
    ui_subheader "推送问题诊断"
    
    echo "  🔍 当前分支: $branch"
    
    # 检查远程配置
    local remotes
    remotes=($(detect_available_remotes))
    echo "  🌐 配置的远程: ${remotes[*]}"
    
    # 检查upstream配置
    local upstream
    upstream=$(get_branch_upstream "$branch")
    if [[ -n "$upstream" ]]; then
        echo "  ⬆️  upstream配置: $upstream"
    else
        echo "  ⬆️  upstream配置: 未设置"
    fi
    
    # 智能推送目标选择测试
    echo "  🎯 智能推送目标选择:"
    local selected_remote
    selected_remote=$(smart_select_push_target "$branch")
    if [[ -n "$selected_remote" ]]; then
        echo "    ✅ 自动选择: $selected_remote"
        echo "    📤 推送命令: git push $selected_remote $branch"
    else
        echo "    ❌ 无法自动选择推送目标"
    fi
    
    # 实际推送测试（dry-run）
    echo "  🧪 实际推送测试 (dry-run):"
    for remote in "${remotes[@]}"; do
        if git push --dry-run "$remote" "$branch" >/dev/null 2>&1; then
            echo "    ✅ $remote: 推送测试成功"
        else
            echo "    ❌ $remote: 推送测试失败"
        fi
    done
    
    echo
}

# 提供推送建议
suggest_push_solutions() {
    local branch="${1:-$(git branch --show-current)}"
    
    ui_subheader "推送解决方案建议"
    
    local remotes
    remotes=($(detect_available_remotes))
    
    if [[ ${#remotes[@]} -eq 0 ]]; then
        echo "  💡 建议1: 添加远程仓库"
        echo "    git remote add origin <your-repo-url>"
        echo
        echo "  💡 建议2: 检查Git配置"
        echo "    git config --list | grep remote"
        return
    fi
    
    # 分析用户的Git配置
    analyze_user_git_config "$branch"
    
    echo
    echo "  💡 手动推送选项:"
    local all_remotes
    all_remotes=($(git remote 2>/dev/null || echo ""))
    
    if [[ ${#all_remotes[@]} -gt 0 ]]; then
        echo "    基于你的配置，可以使用："
        for remote in "${all_remotes[@]}"; do
            local remote_url
            remote_url=$(git config "remote.$remote.url" 2>/dev/null || echo "")
            echo "      gpf pr --push-remote $remote    # 推送到 $remote ($remote_url)"
        done
        echo
        echo "    或者直接使用Git命令："
        for remote in "${all_remotes[@]}"; do
            echo "      git push $remote $branch"
        done
    else
        echo "    gpf pr --push-remote <remote>     # 指定远程仓库推送并创建PR"
        echo "    gpf push --remote <remote>        # 单独推送到指定远程"  
        echo "    git push <remote> $branch         # 原生Git推送"
    fi
    echo
}

# 分析用户Git配置并提供具体推送建议
analyze_user_git_config() {
    local branch="$1"
    
    echo "  🔍 Git配置分析:"
    echo
    
    # 获取所有远程配置
    local all_remotes
    all_remotes=($(git remote 2>/dev/null || echo ""))
    
    if [[ ${#all_remotes[@]} -eq 0 ]]; then
        echo "    ❌ 没有配置远程仓库"
        echo "    💡 标准配置方法:"
        echo "       git remote add origin <your-repo-url>"
        echo "       git push --set-upstream origin $branch"
        return
    fi
    
    echo "    📋 远程仓库配置:"
    for remote in "${all_remotes[@]}"; do
        local fetch_url push_urls
        fetch_url=$(git config "remote.$remote.url" 2>/dev/null || echo "未配置")
        
        # 获取所有pushurl（可能有多个）
        local pushurl_count
        pushurl_count=$(git config --get-all "remote.$remote.pushurl" 2>/dev/null | wc -l | tr -d ' ')
        
        echo "      🌐 $remote:"
        echo "        📥 Fetch: $fetch_url"
        
        if [[ "$pushurl_count" -gt 0 ]]; then
            echo "        📤 Push URL(s):"
            git config --get-all "remote.$remote.pushurl" 2>/dev/null | while read -r pushurl; do
                echo "           • $pushurl"
            done
            
            if [[ "$pushurl_count" -gt 1 ]]; then
                echo "        ✨ 多目标推送: git push $remote $branch"
            else
                echo "        📤 推送命令: git push $remote $branch"
            fi
        else
            echo "        📤 Push: $fetch_url"
            echo "        📤 推送命令: git push $remote $branch"
        fi
        
        echo
    done
    
    # 检查upstream配置
    local upstream_remote upstream_branch
    upstream_remote=$(git config "branch.$branch.remote" 2>/dev/null || echo "")
    upstream_branch=$(git config "branch.$branch.merge" 2>/dev/null | sed 's|refs/heads/||' || echo "")
    
    echo "    ⬆️  分支追踪配置:"
    if [[ -n "$upstream_remote" && -n "$upstream_branch" ]]; then
        echo "       当前分支追踪: $upstream_remote/$upstream_branch"
        echo "       💡 推荐命令: git push (使用已配置的upstream)"
        echo "       💡 或者使用: gpf pr --push-remote $upstream_remote"
    else
        echo "       当前分支未设置upstream"
        
        # 智能推荐
        if [[ " ${all_remotes[*]} " == *" origin "* ]]; then
            echo "       💡 标准推荐: gpf pr --push-remote origin"
            echo "       💡 设置upstream: git push --set-upstream origin $branch"
        elif [[ " ${all_remotes[*]} " == *" all "* ]]; then
            echo "       💡 多平台推送: gpf pr --push-remote all"
        else
            echo "       💡 可选远程: gpf pr --push-remote <${all_remotes[*]}>"
        fi
    fi
    
    echo
    echo "    💡 实际推送测试:"
    for remote in "${all_remotes[@]}"; do
        echo "       测试 $remote: git push --dry-run $remote $branch"
    done
}

# 分析连接失败的原因
analyze_connection_failure() {
    local remote="$1"
    local url="$2"
    
    echo "        🔍 失败分析:"
    
    if [[ "$url" == git@* ]]; then
        echo "        📝 SSH配置 - 检查项:"
        echo "           • SSH密钥是否添加到代理: ssh-add -l"
        echo "           • SSH配置是否正确: cat ~/.ssh/config"
        
        # 提取主机名
        local hostname
        hostname=$(echo "$url" | sed 's/git@\([^:]*\):.*/\1/')
        echo "           • 测试SSH连接: ssh -T git@$hostname"
        
    elif [[ "$url" == https://* ]]; then
        echo "        📝 HTTPS配置 - 检查项:"
        echo "           • 网络连接是否正常"
        echo "           • 认证凭据是否有效"
        echo "           • 是否需要访问令牌"
        
    else
        echo "        📝 未知协议: $url"
    fi
}

# =====================================================
# 主要接口函数
# =====================================================

# 主要的智能推送接口
gpf_smart_push() {
    local branch=""
    local force="false"
    local diagnose="false"
    local help="false"
    local specified_remote=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force="true"
                shift
                ;;
            --diagnose|-d)
                diagnose="true"
                shift
                ;;
            --help|-h)
                help="true"
                shift
                ;;
            --remote|-r)
                if [[ -n "$2" && "$2" != -* ]]; then
                    specified_remote="$2"
                    shift 2
                else
                    ui_error "--remote 选项需要指定远程仓库名称"
                    return 1
                fi
                ;;
            *)
                if [[ -z "$branch" ]]; then
                    branch="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ "$help" == "true" ]]; then
        show_smart_push_help
        return 0
    fi
    
    if [[ "$diagnose" == "true" ]]; then
        diagnose_push_issues "$branch"
        suggest_push_solutions "$branch"
        return 0
    fi
    
    # 执行智能推送
    if [[ -n "$specified_remote" ]]; then
        smart_push_to_remote "$branch" "$specified_remote" "$force"
    else
        smart_push_branch "$branch" "$force"
    fi
}

# 推送到指定远程
smart_push_to_remote() {
    local branch="${1:-$(git branch --show-current)}"
    local remote="$2"
    local force="${3:-false}"
    local set_upstream="${4:-true}"
    
    if [[ -z "$branch" || -z "$remote" ]]; then
        ui_error "分支名和远程仓库名不能为空"
        return 1
    fi
    
    ui_loading "推送分支到指定远程: $branch → $remote"
    
    # 验证远程存在
    if ! git remote | grep -q "^$remote$"; then
        ui_error "远程仓库不存在: $remote"
        echo "  可用的远程仓库: $(git remote | tr '\n' ' ')"
        return 1
    fi
    
    # 构建推送命令
    local push_cmd="git push"
    
    if [[ "$force" == "true" ]]; then
        push_cmd="$push_cmd --force-with-lease"
        ui_warning "使用强制推送模式"
    fi
    
    if [[ "$set_upstream" == "true" ]]; then
        push_cmd="$push_cmd --set-upstream"
    fi
    
    push_cmd="$push_cmd $remote $branch"
    
    ui_info "执行推送: $push_cmd"
    
    # 执行推送
    if eval "$push_cmd"; then
        ui_success "分支推送成功: $branch → $remote"
        
        # 缓存成功的推送配置
        cache_successful_push_config "$branch" "$remote"
        
        return 0
    else
        ui_error "分支推送失败: $branch → $remote"
        
        # 提供具体的错误分析
        echo
        ui_subheader "错误分析"
        analyze_connection_failure "$remote" "$(git config "remote.$remote.url" 2>/dev/null || echo "未知")"
        
        return 1
    fi
}

# 显示帮助信息
show_smart_push_help() {
    cat << EOF
GPF 智能推送工具

用法:
  gpf push [选项] [分支名]

选项:
  --force, -f     强制推送（使用 --force-with-lease）
  --diagnose, -d  诊断推送问题并提供解决建议
  --help, -h      显示此帮助信息

功能:
  - 自动检测最佳推送目标远程仓库
  - 智能处理不同的Git配置环境
  - 支持多远程仓库配置
  - 提供详细的错误诊断和解决建议

示例:
  gpf push                          # 推送当前分支到智能选择的远程
  gpf push feature-branch           # 推送指定分支
  gpf push --force                  # 强制推送当前分支
  gpf push --diagnose               # 诊断推送问题

EOF
}