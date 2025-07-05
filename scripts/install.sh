#!/usr/bin/env bash

# NewGPF Installation Script
# 完整安装GPF及其依赖，包括VSCode配置和Git hooks

set -euo pipefail

# Constants
readonly GPF_VERSION="2.0.0"
readonly GPF_REPO="https://github.com/your-repo/git-pr-cli.git"
readonly GPF_INSTALL_DIR="$HOME/.local/share/newgpf"
readonly GPF_BIN_DIR="$HOME/.local/bin"
readonly GPF_SYMLINK="$GPF_BIN_DIR/git-pr-flow"
readonly GPF_ALIAS="$GPF_BIN_DIR/gpf"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Utility functions
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

log_header() {
    echo -e "${GREEN}┌─ $* ─$(printf '%*s' $((50 - ${#1})) '' | tr ' ' '─')┐${NC}"
}

log_footer() {
    echo -e "${GREEN}└─$(printf '%*s' 50 '' | tr ' ' '─')┘${NC}"
}

# Check requirements
check_requirements() {
    log_info "检查系统要求..."
    
    # Check if Git is installed
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git未安装，请先安装Git"
        exit 1
    fi
    
    # Check Git version (minimum 2.25)
    local git_version
    git_version=$(git --version | sed 's/git version //')
    local git_major git_minor
    git_major=$(echo "$git_version" | cut -d. -f1)
    git_minor=$(echo "$git_version" | cut -d. -f2)
    
    if [[ $git_major -lt 2 ]] || [[ $git_major -eq 2 && $git_minor -lt 25 ]]; then
        log_error "需要Git 2.25+版本，当前版本：$git_version"
        exit 1
    fi
    
    # Check if bash is available
    if ! command -v bash >/dev/null 2>&1; then
        log_error "Bash不可用"
        exit 1
    fi
    
    log_success "系统要求检查通过"
}

# Install GitHub CLI if not present
install_github_cli() {
    log_info "检查GitHub CLI (gh)..."
    
    if command -v gh >/dev/null 2>&1; then
        log_success "GitHub CLI已安装: $(gh --version | head -1)"
        return 0
    fi
    
    log_info "GitHub CLI未安装，正在安装..."
    
    # Detect OS and install accordingly
    case "$(uname -s)" in
        Darwin*)
            if command -v brew >/dev/null 2>&1; then
                brew install gh
            else
                log_error "请先安装Homebrew，或手动安装GitHub CLI"
                log_info "访问: https://cli.github.com/"
                exit 1
            fi
            ;;
        Linux*)
            # Try different package managers
            if command -v apt >/dev/null 2>&1; then
                # Ubuntu/Debian
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt update && sudo apt install gh
            elif command -v yum >/dev/null 2>&1; then
                # CentOS/RHEL
                sudo yum install -y yum-utils
                sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
                sudo yum install gh
            elif command -v dnf >/dev/null 2>&1; then
                # Fedora
                sudo dnf install gh
            elif command -v pacman >/dev/null 2>&1; then
                # Arch Linux
                sudo pacman -S github-cli
            else
                log_error "无法自动安装GitHub CLI，请手动安装"
                log_info "访问: https://cli.github.com/"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的操作系统，请手动安装GitHub CLI"
            log_info "访问: https://cli.github.com/"
            exit 1
            ;;
    esac
    
    if command -v gh >/dev/null 2>&1; then
        log_success "GitHub CLI安装成功: $(gh --version | head -1)"
    else
        log_error "GitHub CLI安装失败"
        exit 1
    fi
}

# Create necessary directories
create_directories() {
    log_info "创建安装目录..."
    
    # Create install directory
    if [[ ! -d "$GPF_INSTALL_DIR" ]]; then
        mkdir -p "$GPF_INSTALL_DIR"
        log_success "创建安装目录: $GPF_INSTALL_DIR"
    fi
    
    # Create bin directory
    if [[ ! -d "$GPF_BIN_DIR" ]]; then
        mkdir -p "$GPF_BIN_DIR"
        log_success "创建bin目录: $GPF_BIN_DIR"
    fi
}

# Download and install GPF
download_and_install() {
    log_info "下载NewGPF..."
    
    # Remove existing installation if present
    if [[ -d "$GPF_INSTALL_DIR" ]]; then
        log_warn "移除现有安装..."
        rm -rf "$GPF_INSTALL_DIR"
    fi
    
    # Clone the repository
    if ! git clone "$GPF_REPO" "$GPF_INSTALL_DIR"; then
        log_error "下载仓库失败"
        exit 1
    fi
    
    # Switch to newgpf branch
    cd "$GPF_INSTALL_DIR"
    git checkout newgpf || {
        log_warn "newgpf分支不存在，使用默认分支"
    }
    
    log_success "NewGPF下载完成: $GPF_INSTALL_DIR"
}

# Create symbolic links
create_symlinks() {
    log_info "创建符号链接..."
    
    # Remove existing symlinks
    [[ -L "$GPF_SYMLINK" ]] && rm "$GPF_SYMLINK"
    [[ -L "$GPF_ALIAS" ]] && rm "$GPF_ALIAS"
    
    # Create symlink to main executable
    if ! ln -s "$GPF_INSTALL_DIR/bin/git-pr-flow" "$GPF_SYMLINK"; then
        log_error "创建符号链接失败: $GPF_SYMLINK"
        exit 1
    fi
    
    # Create alias symlink
    if ! ln -s "$GPF_INSTALL_DIR/bin/git-pr-flow" "$GPF_ALIAS"; then
        log_error "创建别名链接失败: $GPF_ALIAS"
        exit 1
    fi
    
    # Make executable
    chmod +x "$GPF_INSTALL_DIR/bin/git-pr-flow"
    
    log_success "符号链接创建完成"
}

# Configure VSCode for worktree support
configure_vscode() {
    log_info "配置VSCode worktree支持..."
    
    # Detect VSCode settings path
    local vscode_settings=""
    case "$(uname -s)" in
        Darwin*)
            vscode_settings="$HOME/Library/Application Support/Code/User/settings.json"
            ;;
        Linux*)
            vscode_settings="$HOME/.config/Code/User/settings.json"
            ;;
        MINGW*|CYGWIN*|MSYS*)
            vscode_settings="$APPDATA/Code/User/settings.json"
            ;;
    esac
    
    if [[ -z "$vscode_settings" ]]; then
        log_warn "无法检测VSCode设置路径，跳过自动配置"
        return 0
    fi
    
    # Check if VSCode is installed
    if [[ ! -f "$vscode_settings" ]]; then
        log_warn "VSCode未安装或未运行过，跳过自动配置"
        log_info "请在安装VSCode后手动配置worktree支持"
        return 0
    fi
    
    # Check if jq is available for JSON manipulation
    if ! command -v jq >/dev/null 2>&1; then
        log_warn "jq未安装，无法自动配置VSCode，请手动配置"
        cat << 'EOF'
请在VSCode设置中添加以下配置：
{
  "git.autoRepositoryDetection": "subFolders",
  "git.repositoryScanMaxDepth": 2
}
EOF
        return 0
    fi
    
    # Backup existing settings
    local backup_file="$vscode_settings.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$vscode_settings" "$backup_file"
    log_info "备份VSCode设置: $backup_file"
    
    # Add GPF configuration if not exists
    if ! grep -q "git.autoRepositoryDetection" "$vscode_settings"; then
        # Update settings with jq
        jq '. + {"git.autoRepositoryDetection": "subFolders", "git.repositoryScanMaxDepth": 2}' "$vscode_settings" > "$vscode_settings.tmp"
        mv "$vscode_settings.tmp" "$vscode_settings"
        log_success "VSCode配置已更新"
        
        # Show reload instruction
        echo ""
        log_warn "重要：请在VSCode中执行以下命令使配置生效："
        echo -e "${YELLOW}  Ctrl+Shift+P${NC} (Windows/Linux) 或 ${YELLOW}⌘+Shift+P${NC} (macOS)"
        echo -e "  输入并执行：${GREEN}Developer: Reload Window${NC}"
        echo ""
    else
        log_success "VSCode配置已存在"
    fi
}

# Install Git hooks
install_git_hooks() {
    log_info "安装Git hooks..."
    
    # Check if we're in a Git repository
    local current_dir="$PWD"
    local install_hooks=false
    
    # If user runs this in a GPF project, install hooks immediately
    if [[ -f "bin/git-pr-flow" && -d ".git" ]]; then
        install_hooks=true
    elif [[ -f "$GPF_INSTALL_DIR/scripts/install-hooks.sh" ]]; then
        # Install hooks to the GPF installation directory for later use
        cd "$GPF_INSTALL_DIR"
        if [[ -d ".git" ]]; then
            install_hooks=true
        fi
    fi
    
    if [[ "$install_hooks" == true ]]; then
        if [[ -f "scripts/install-hooks.sh" ]]; then
            ./scripts/install-hooks.sh
            log_success "Git hooks安装完成"
        else
            log_warn "Git hooks脚本未找到，跳过hooks安装"
        fi
    else
        log_info "非Git仓库环境，跳过hooks安装"
        log_info "在GPF项目中运行 './scripts/install-hooks.sh' 来安装hooks"
    fi
    
    # Return to original directory
    cd "$current_dir"
}

# Update PATH if needed
update_path() {
    log_info "检查PATH配置..."
    
    local shell_config=""
    local shell_name
    shell_name=$(basename "$SHELL")
    
    case "$shell_name" in
        bash)
            if [[ -f "$HOME/.bash_profile" ]]; then
                shell_config="$HOME/.bash_profile"
            elif [[ -f "$HOME/.bashrc" ]]; then
                shell_config="$HOME/.bashrc"
            fi
            ;;
        zsh)
            shell_config="$HOME/.zshrc"
            ;;
        fish)
            shell_config="$HOME/.config/fish/config.fish"
            ;;
    esac
    
    # Check if PATH already contains the bin directory
    if [[ ":$PATH:" == *":$GPF_BIN_DIR:"* ]]; then
        log_success "PATH已配置"
        return 0
    fi
    
    if [[ -n "$shell_config" ]]; then
        log_info "添加 $GPF_BIN_DIR 到PATH: $shell_config"
        echo "" >> "$shell_config"
        echo "# NewGPF" >> "$shell_config"
        echo "export PATH=\"\$PATH:$GPF_BIN_DIR\"" >> "$shell_config"
        log_success "PATH已更新: $shell_config"
        log_warn "请重启shell或执行: source $shell_config"
    else
        log_warn "无法检测shell配置文件"
        log_warn "请手动添加 $GPF_BIN_DIR 到PATH"
    fi
}

# Test installation
test_installation() {
    log_info "测试安装..."
    
    # Test if executable is accessible
    if [[ -x "$GPF_SYMLINK" ]]; then
        # Test version command
        if "$GPF_SYMLINK" --version >/dev/null 2>&1; then
            log_success "安装测试通过"
            return 0
        fi
    fi
    
    log_error "安装测试失败"
    return 1
}

# Show completion message
show_completion() {
    log_header "NewGPF 安装完成！"
    echo -e "${GREEN}│${NC} NewGPF v$GPF_VERSION 安装成功！"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} 安装位置: $GPF_INSTALL_DIR"
    echo -e "${GREEN}│${NC} 可执行文件:"
    echo -e "${GREEN}│${NC}   - git-pr-flow (完整命令)"
    echo -e "${GREEN}│${NC}   - gpf (简短别名)"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} 已配置功能:"
    echo -e "${GREEN}│${NC}   ✅ GitHub CLI 集成"
    echo -e "${GREEN}│${NC}   ✅ VSCode worktree 支持"
    echo -e "${GREEN}│${NC}   ✅ Git hooks 开发流程控制"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} 快速开始:"
    echo -e "${GREEN}│${NC}   cd your-project"
    echo -e "${GREEN}│${NC}   ./scripts/install-hooks.sh  # 在项目中安装hooks"
    echo -e "${GREEN}│${NC}   gpf start -e your-epic develop"
    echo -e "${GREEN}│${NC}   gpf start -ef your-feature your-epic"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} 获取帮助:"
    echo -e "${GREEN}│${NC}   gpf --help"
    log_footer
    
    if [[ ":$PATH:" != *":$GPF_BIN_DIR:"* ]]; then
        echo ""
        log_warn "别忘了重启shell或执行:"
        log_warn "  source ~/.bashrc  (或你的shell配置文件)"
    fi
    
    # Show VSCode reload reminder
    echo ""
    log_info "如果使用VSCode，请记得重新加载窗口:"
    echo -e "  ${YELLOW}Ctrl+Shift+P${NC} > ${GREEN}Developer: Reload Window${NC}"
}

# Main installation function
main() {
    log_header "NewGPF 安装器 v$GPF_VERSION"
    echo -e "${GREEN}│${NC} 安装NewGPF - 现代化PR开发工具"
    echo -e "${GREEN}│${NC} 包含VSCode配置和开发流程控制"
    log_footer
    echo ""
    
    check_requirements
    install_github_cli
    create_directories
    download_and_install
    create_symlinks
    configure_vscode
    install_git_hooks
    update_path
    
    if test_installation; then
        echo ""
        show_completion
    else
        echo ""
        log_error "安装完成但测试失败"
        log_error "请手动检查安装"
        exit 1
    fi
}

# Handle script interruption
trap 'echo ""; log_error "安装中断"; exit 1' INT TERM

# Run main function
main "$@"