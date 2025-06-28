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

# =====================================================
# 智能推送策略
# =====================================================

# 智能选择推送目标
smart_select_push_target() {
    local branch="${1:-$(git branch --show-current)}"
    local force_mode="${2:-false}"
    
    if [[ -z "$branch" ]]; then
        ui_error "无法确定当前分支"
        return 1
    fi
    
    log_debug "为分支 $branch 选择推送目标"
    
    # 1. 检查分支的upstream配置
    local upstream
    upstream=$(get_branch_upstream "$branch")
    if [[ -n "$upstream" ]]; then
        local upstream_remote="${upstream%/*}"
        if test_remote_connectivity "$upstream_remote"; then
            log_debug "使用upstream配置: $upstream"
            echo "$upstream_remote"
            return 0
        else
            ui_warning "upstream远程 $upstream_remote 不可达，尝试其他远程"
        fi
    fi
    
    # 2. 检测并测试可用的远程
    local remotes
    remotes=($(detect_available_remotes))
    
    if [[ ${#remotes[@]} -eq 0 ]]; then
        ui_error "没有可用的远程仓库"
        return 1
    fi
    
    log_debug "检测到 ${#remotes[@]} 个远程仓库: ${remotes[*]}"
    
    # 3. 测试远程连接性和权限
    for remote in "${remotes[@]}"; do
        ui_info "测试远程仓库: $remote"
        
        if test_remote_connectivity "$remote" 5; then
            if [[ "$force_mode" == "true" ]] || test_remote_push_permission "$remote" "$branch"; then
                ui_success "选择推送目标: $remote"
                echo "$remote"
                return 0
            else
                ui_warning "远程 $remote 可连接但无推送权限"
            fi
        else
            ui_warning "远程 $remote 不可达"
        fi
    done
    
    ui_error "没有找到可用的推送目标"
    return 1
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
    
    # 测试远程连接
    echo "  🔗 远程连接测试:"
    for remote in "${remotes[@]}"; do
        if test_remote_connectivity "$remote" 3; then
            echo "    ✅ $remote: 连接正常"
        else
            echo "    ❌ $remote: 连接失败"
        fi
    done
    
    # 推送权限测试
    echo "  🔐 推送权限测试:"
    for remote in "${remotes[@]}"; do
        if test_remote_push_permission "$remote" "$branch"; then
            echo "    ✅ $remote: 有推送权限"
        else
            echo "    ❌ $remote: 无推送权限或连接失败"
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
    
    echo "  💡 建议1: 使用智能推送"
    echo "    gpf push  # 使用GPF智能推送功能"
    echo
    
    echo "  💡 建议2: 手动指定远程"
    echo "    git push origin $branch"
    echo
    
    echo "  💡 建议3: 强制推送（谨慎使用）"
    echo "    gpf push --force"
    echo
    
    echo "  💡 建议4: 设置upstream"
    echo "    git push --set-upstream origin $branch"
    echo
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
    smart_push_branch "$branch" "$force"
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