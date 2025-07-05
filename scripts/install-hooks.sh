#!/bin/bash

# NewGPF Git Hooks Installation Script
# 安装Git hooks以强制GPF工作流规范

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOKS_DIR="$SCRIPT_DIR/hooks"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠️${NC} $*"
}

log_error() {
    echo -e "${RED}❌${NC} $*"
}

# 检查是否在Git仓库中
check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "当前目录不是Git仓库"
        return 1
    fi
    return 0
}

# 检查是否是GPF项目
check_gpf_project() {
    if [[ ! -f "$PROJECT_ROOT/bin/git-pr-flow" ]]; then
        log_error "这不是一个GPF项目（未找到 bin/git-pr-flow）"
        return 1
    fi
    return 0
}

# 安装单个hook
install_hook() {
    local hook_name="$1"
    local hook_source="$HOOKS_DIR/$hook_name"
    local hook_target=".git/hooks/$hook_name"
    
    if [[ ! -f "$hook_source" ]]; then
        log_error "Hook文件不存在: $hook_source"
        return 1
    fi
    
    # 备份现有hook
    if [[ -f "$hook_target" ]]; then
        local backup_file="$hook_target.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "备份现有hook: $hook_target -> $backup_file"
        mv "$hook_target" "$backup_file"
    fi
    
    # 复制新hook
    cp "$hook_source" "$hook_target"
    chmod +x "$hook_target"
    
    log_success "已安装 $hook_name hook"
}

# 安装所有hooks
install_all_hooks() {
    log_info "开始安装GPF Git hooks..."
    
    # 创建hooks目录（如果不存在）
    mkdir -p .git/hooks
    
    # 安装pre-commit hook
    install_hook "pre-commit"
    
    # 可以在这里添加更多hooks
    # install_hook "pre-push"
    # install_hook "commit-msg"
    
    log_success "所有GPF Git hooks安装完成"
}

# 验证hooks安装
verify_hooks() {
    log_info "验证hooks安装..."
    
    local hooks_to_check=("pre-commit")
    local all_ok=true
    
    for hook in "${hooks_to_check[@]}"; do
        local hook_file=".git/hooks/$hook"
        if [[ -f "$hook_file" && -x "$hook_file" ]]; then
            log_success "$hook hook 已正确安装"
        else
            log_error "$hook hook 安装失败"
            all_ok=false
        fi
    done
    
    if [[ "$all_ok" == true ]]; then
        log_success "所有hooks验证通过"
        return 0
    else
        log_error "部分hooks验证失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo ""
    echo -e "${GREEN}🎯 GPF Git Hooks 安装完成！${NC}"
    echo ""
    echo -e "${BLUE}📋 Hooks 功能说明：${NC}"
    echo -e "  • ${GREEN}pre-commit${NC}: 防止在Epic分支直接提交"
    echo -e "    - 只在GPF管理的项目中生效"
    echo -e "    - 强制使用Feature分支进行开发"
    echo -e "    - 对非GPF项目完全透明"
    echo ""
    echo -e "${BLUE}🔧 开发流程：${NC}"
    echo -e "  1. ${GREEN}Epic分支${NC} (如 epic-auth-e)：仅用于整合Feature"
    echo -e "  2. ${GREEN}Feature分支${NC} (如 epic-auth-login-ef)：实际开发"
    echo -e "  3. ${GREEN}工作流程${NC}: Feature → Epic → Develop"
    echo ""
    echo -e "${BLUE}💡 如果需要提交到Epic分支：${NC}"
    echo -e "  • 创建Feature分支: ${GREEN}gpf start -ef <feature> <epic>${NC}"
    echo -e "  • 在Feature分支开发并提交"
    echo -e "  • 将Feature合并到Epic分支"
    echo ""
    echo -e "${YELLOW}⚠️  只有在 .worktrees/ 目录下的分支才会被严格检查${NC}"
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}🚀 NewGPF Git Hooks 安装器${NC}"
    echo ""
    
    # 检查环境
    if ! check_git_repo; then
        exit 1
    fi
    
    if ! check_gpf_project; then
        exit 1
    fi
    
    # 安装hooks
    install_all_hooks
    
    # 验证安装
    if verify_hooks; then
        show_usage
    else
        log_error "安装验证失败，请检查错误信息"
        exit 1
    fi
}

# 处理命令行参数
case "${1:-}" in
    --help|-h)
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h     显示此帮助信息"
        echo "  --uninstall    卸载GPF hooks"
        echo ""
        echo "描述:"
        echo "  安装GPF Git hooks以强制正确的开发工作流"
        echo "  防止在Epic分支直接提交代码"
        exit 0
        ;;
    --uninstall)
        log_info "卸载GPF hooks..."
        rm -f .git/hooks/pre-commit
        # 恢复备份（如果存在）
        if ls .git/hooks/pre-commit.backup-* >/dev/null 2>&1; then
            latest_backup=$(ls -t .git/hooks/pre-commit.backup-* | head -1)
            mv "$latest_backup" .git/hooks/pre-commit
            log_success "已恢复备份的pre-commit hook"
        fi
        log_success "GPF hooks已卸载"
        exit 0
        ;;
    "")
        # 默认安装
        main
        ;;
    *)
        log_error "未知选项: $1"
        echo "使用 --help 查看帮助信息"
        exit 1
        ;;
esac