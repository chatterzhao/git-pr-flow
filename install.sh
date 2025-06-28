#!/usr/bin/env bash

# Git PR Flow (GPF) Installation Script
# Version: 0.1.0-mvp
# Description: Install Git PR Flow CLI tool for high-quality PR development

set -euo pipefail

# Constants
readonly GPF_VERSION="0.1.0-mvp"
readonly GPF_REPO="https://github.com/chatterzhao/git-pr-flow.git"
readonly GPF_INSTALL_DIR="$HOME/.local/share/git-pr-flow"
readonly GPF_BIN_DIR="$HOME/.local/bin"
readonly GPF_SYMLINK="$GPF_BIN_DIR/git-pr-flow"
readonly GPF_ALIAS="$GPF_BIN_DIR/gpf"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
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
    log_info "Checking system requirements..."
    
    # Check if Git is installed
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is not installed. Please install Git first."
        exit 1
    fi
    
    # Check Git version (minimum 2.20)
    local git_version
    git_version=$(git --version | sed 's/git version //')
    local git_major git_minor
    git_major=$(echo "$git_version" | cut -d. -f1)
    git_minor=$(echo "$git_version" | cut -d. -f2)
    
    if [[ $git_major -lt 2 ]] || [[ $git_major -eq 2 && $git_minor -lt 20 ]]; then
        log_error "Git version 2.20+ is required. Current version: $git_version"
        exit 1
    fi
    
    # Check if bash is available
    if ! command -v bash >/dev/null 2>&1; then
        log_error "Bash is not available."
        exit 1
    fi
    
    log_success "Requirements check passed"
}

# Create necessary directories
create_directories() {
    log_info "Creating installation directories..."
    
    # Create install directory
    if [[ ! -d "$GPF_INSTALL_DIR" ]]; then
        mkdir -p "$GPF_INSTALL_DIR"
        log_success "Created install directory: $GPF_INSTALL_DIR"
    fi
    
    # Create bin directory
    if [[ ! -d "$GPF_BIN_DIR" ]]; then
        mkdir -p "$GPF_BIN_DIR"
        log_success "Created bin directory: $GPF_BIN_DIR"
    fi
}

# Download and install GPF
download_and_install() {
    log_info "Downloading Git PR Flow..."
    
    # Remove existing installation if present
    if [[ -d "$GPF_INSTALL_DIR" ]]; then
        log_warn "Removing existing installation..."
        rm -rf "$GPF_INSTALL_DIR"
    fi
    
    # Clone the repository
    if ! git clone "$GPF_REPO" "$GPF_INSTALL_DIR"; then
        log_error "Failed to clone repository"
        exit 1
    fi
    
    log_success "Downloaded Git PR Flow to $GPF_INSTALL_DIR"
}

# Create symbolic links
create_symlinks() {
    log_info "Creating symbolic links..."
    
    # Remove existing symlinks
    [[ -L "$GPF_SYMLINK" ]] && rm "$GPF_SYMLINK"
    [[ -L "$GPF_ALIAS" ]] && rm "$GPF_ALIAS"
    
    # Create symlink to main executable
    if ! ln -s "$GPF_INSTALL_DIR/bin/git-pr-flow" "$GPF_SYMLINK"; then
        log_error "Failed to create symlink: $GPF_SYMLINK"
        exit 1
    fi
    
    # Create alias symlink
    if ! ln -s "$GPF_INSTALL_DIR/bin/git-pr-flow" "$GPF_ALIAS"; then
        log_error "Failed to create alias symlink: $GPF_ALIAS"
        exit 1
    fi
    
    # Make executable
    chmod +x "$GPF_INSTALL_DIR/bin/git-pr-flow"
    
    log_success "Created symbolic links"
}

# Update PATH if needed
update_path() {
    log_info "Checking PATH configuration..."
    
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
        log_success "PATH already configured"
        return 0
    fi
    
    if [[ -n "$shell_config" ]]; then
        log_info "Adding $GPF_BIN_DIR to PATH in $shell_config"
        echo "" >> "$shell_config"
        echo "# Git PR Flow" >> "$shell_config"
        echo "export PATH=\"\$PATH:$GPF_BIN_DIR\"" >> "$shell_config"
        log_success "Updated PATH in $shell_config"
        log_warn "Please restart your shell or run: source $shell_config"
    else
        log_warn "Could not detect shell configuration file."
        log_warn "Please add $GPF_BIN_DIR to your PATH manually."
    fi
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Test if executable is accessible
    if [[ -x "$GPF_SYMLINK" ]]; then
        # Test version command
        if "$GPF_SYMLINK" --version >/dev/null 2>&1; then
            log_success "Installation test passed"
            return 0
        fi
    fi
    
    log_error "Installation test failed"
    return 1
}

# Show completion message
show_completion() {
    log_header "Installation Complete!"
    echo -e "${GREEN}│${NC} Git PR Flow v$GPF_VERSION has been installed successfully!"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} Installation location: $GPF_INSTALL_DIR"
    echo -e "${GREEN}│${NC} Executable links:"
    echo -e "${GREEN}│${NC}   - git-pr-flow (full command)"
    echo -e "${GREEN}│${NC}   - gpf (short alias)"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} Quick start:"
    echo -e "${GREEN}│${NC}   gpf init your-feature-name develop"
    echo -e "${GREEN}│${NC}   gpf start your-feature-name/sub-feature"
    echo -e "${GREEN}│${NC}"
    echo -e "${GREEN}│${NC} Get help:"
    echo -e "${GREEN}│${NC}   gpf --help"
    log_footer
    
    if [[ ":$PATH:" != *":$GPF_BIN_DIR:"* ]]; then
        echo ""
        log_warn "Don't forget to restart your shell or run:"
        log_warn "  source ~/.bashrc  (or your shell config file)"
    fi
}

# Main installation function
main() {
    log_header "Git PR Flow Installer v$GPF_VERSION"
    echo -e "${GREEN}│${NC} Installing Git PR Flow - High-quality PR development tool"
    log_footer
    echo ""
    
    check_requirements
    create_directories
    download_and_install
    create_symlinks
    update_path
    
    if test_installation; then
        echo ""
        show_completion
    else
        echo ""
        log_error "Installation completed but tests failed."
        log_error "Please check the installation manually."
        exit 1
    fi
}

# Handle script interruption
trap 'echo ""; log_error "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"