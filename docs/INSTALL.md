# GPF 安装指南

> 📖 **相关文档**: [主文档](../README.md) | [架构设计](ARCHITECTURE.md) | [命令详细](COMMANDS.md) | [核心组件](CORE-COMPONENTS.md)

GPF作为**PR友好工具**，需要与GitHub深度集成。本安装指南将引导您完成GPF和必要依赖的安装。

## 🎯 安装概述

GPF的完整功能依赖以下组件：
- **GPF本体**：核心CLI工具
- **GitHub CLI (gh)**：用于GitHub PR状态检查和操作
- **Git**：版本控制基础（通常已安装）

## 🚀 一键安装（推荐）

我们提供了智能安装脚本，会根据您的操作系统自动安装所有依赖：

```bash
# 下载并运行安装脚本
curl -fsSL https://raw.githubusercontent.com/your-repo/git-pr-cli/main/scripts/install.sh | bash

# 或者手动下载后运行
wget https://raw.githubusercontent.com/your-repo/git-pr-cli/main/scripts/install.sh
chmod +x install.sh
./install.sh
```

安装脚本会自动：
1. 检测操作系统类型
2. 安装GitHub CLI (gh)
3. 安装GPF本体
4. 配置环境变量
5. 配置VSCode worktree支持
6. 安装Git hooks（强制GPF工作流规范）
7. 验证安装完成

## 📋 系统要求

### 支持的操作系统
- **macOS**: 10.15+ (Catalina及以上)
- **Linux**: Ubuntu 18.04+, CentOS 7+, 其他主流发行版
- **Windows**: Windows 10+ (通过WSL2或Git Bash)

### 必需软件
- **Git**: 2.25+ (通常系统已安装)
- **Bash**: 4.0+ (macOS/Linux默认，Windows需WSL或Git Bash)

## 🔧 分步安装指南

如果您选择手动安装，请按以下步骤操作：

### 第一步：安装GitHub CLI (gh)

GitHub CLI是GPF实现完整PR功能的关键依赖。

#### macOS

```bash
# 使用Homebrew（推荐）
brew install gh

# 使用MacPorts
sudo port install gh

# 使用官方安装包
curl -fsSL https://github.com/cli/cli/releases/latest/download/gh_*_macOS_amd64.tar.gz | tar -xz
sudo mv gh*/bin/gh /usr/local/bin/
```

#### Ubuntu/Debian

```bash
# 添加GitHub CLI官方源
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# 安装
sudo apt update
sudo apt install gh
```

#### CentOS/RHEL/Fedora

```bash
# CentOS/RHEL
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install gh

# Fedora
sudo dnf install gh
```

#### Arch Linux

```bash
sudo pacman -S github-cli
```

#### Windows

```powershell
# 使用Chocolatey
choco install gh

# 使用Scoop
scoop install gh

# 使用winget
winget install --id GitHub.cli

# 手动安装：下载exe文件
# https://github.com/cli/cli/releases/latest
```

### 第二步：验证GitHub CLI安装

```bash
# 检查gh版本
gh --version

# 登录GitHub（必需）
gh auth login

# 验证登录状态
gh auth status
```

### 第三步：安装GPF

```bash
# 克隆GPF仓库
git clone https://github.com/your-repo/git-pr-cli.git
cd git-pr-cli

# 运行安装脚本
./scripts/install-gpf.sh

# 或手动安装
sudo ln -sf "$(pwd)/bin/git-pr-flow" /usr/local/bin/gpf
```

### 第四步：配置环境

```bash
# 添加到PATH（如果安装脚本未自动完成）
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc

# 重新加载shell配置
source ~/.bashrc  # 或 source ~/.zshrc
```

## ✅ 安装验证

完成安装后，请运行以下命令验证：

```bash
# 验证GPF安装
gpf --version
gpf --help

# 验证GitHub集成
gh auth status
gh repo view  # 在Git仓库中运行

# 验证完整功能
cd your-project
gpf status
```

预期输出：
```
✅ GPF v2.0.0 已安装
✅ GitHub CLI v2.x.x 已安装并认证
✅ Git v2.x.x 已安装
✅ 所有依赖检查通过
```

## 🔧 高级配置

### VSCode Worktree支持配置

GPF使用Git worktree创建隔离的开发环境。为了让VSCode正确跟踪worktree中的Git状态，需要配置VSCode支持子目录Git检测。

**重要提示：配置后需要重新加载VSCode窗口才能生效！**

**方法1：安装脚本自动配置（推荐）**
```bash
# 一键安装脚本会自动配置VSCode并提示重新加载
curl -fsSL https://raw.githubusercontent.com/your-repo/git-pr-cli/main/scripts/install.sh | bash
```

**方法2：手动配置VSCode**
在VSCode设置中添加以下配置：

```json
{
  "git.autoRepositoryDetection": "subFolders",
  "git.repositoryScanMaxDepth": 2
}
```

**配置步骤：**
1. 打开VSCode设置 (⌘+, 或 Ctrl+,)
2. 点击右上角"打开设置(JSON)"图标
3. 添加上述配置到settings.json
4. 保存设置文件
5. **重要：执行命令重新加载VSCode窗口**
   - 按 `Ctrl+Shift+P` (Windows/Linux) 或 `⌘+Shift+P` (macOS)
   - 输入并执行：`Developer: Reload Window`

**或者通过命令行自动配置：**
```bash
# macOS/Linux 自动配置脚本
cat > ~/.vscode-gpf-config.sh << 'EOF'
#!/bin/bash
VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
# Linux路径: "$HOME/.config/Code/User/settings.json"

# 备份现有配置
cp "$VSCODE_SETTINGS" "$VSCODE_SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"

# 添加GPF配置（如果不存在）
if ! grep -q "git.autoRepositoryDetection" "$VSCODE_SETTINGS"; then
    # 创建临时文件添加配置
    jq '. + {"git.autoRepositoryDetection": "subFolders", "git.repositoryScanMaxDepth": 2}' "$VSCODE_SETTINGS" > "$VSCODE_SETTINGS.tmp"
    mv "$VSCODE_SETTINGS.tmp" "$VSCODE_SETTINGS"
    echo "✅ VSCode配置已更新"
    echo "⚠️  请在VSCode中执行 Ctrl+Shift+P > 'Developer: Reload Window'"
else
    echo "✅ VSCode配置已存在"
fi
EOF

chmod +x ~/.vscode-gpf-config.sh && ~/.vscode-gpf-config.sh
```

**配置效果：**
- ✅ VSCode会自动检测 `.worktrees/` 下的所有Git仓库
- ✅ 每个worktree都有独立的Git状态显示
- ✅ 源代码管理面板正确显示当前worktree的变更
- ✅ Git操作（提交、推送等）在正确的worktree环境中执行

**验证配置：**
```bash
# 创建一个Epic环境
gpf start -e test develop

# 在VSCode中打开项目根目录
# 重新加载窗口后，源代码管理面板应该显示多个仓库：
# - git-pr-cli (根目录)
# - epic-test-e (.worktrees/epic-test-e)
```

**常见问题：**
- **Q**: 配置后VSCode仍然不显示worktree仓库？
- **A**: 确保执行了 `Developer: Reload Window` 命令，这是必需步骤
- **Q**: 如何检查配置是否生效？
- **A**: 在VSCode中查看源代码管理面板，应该显示多个Git仓库图标

### GitHub认证配置

GPF需要GitHub访问权限来检查PR状态：

```bash
# 配置GitHub认证（选择HTTPS）
gh auth login

# 配置默认仓库
gh repo set-default

# 验证权限
gh api user
```

### Git Hooks配置（开发流程控制）

GPF安装时会自动设置Git hooks来强制正确的开发工作流，防止在Epic分支直接开发。

**自动安装（推荐）：**
```bash
# 一键安装脚本会自动配置hooks
curl -fsSL https://raw.githubusercontent.com/your-repo/git-pr-cli/main/scripts/install.sh | bash
```

**手动安装hooks：**
```bash
# 在GPF项目根目录运行
./scripts/install-hooks.sh

# 验证安装
ls -la .git/hooks/pre-commit
```

**Hooks功能说明：**

1. **pre-commit hook**：
   - 🚫 **阻止在Epic分支直接提交**（如 `epic-auth-e`）
   - ✅ **允许在Feature分支提交**（如 `epic-auth-e-login-ef`）
   - 🎯 **只在GPF管理的项目中生效**（检测 `bin/git-pr-flow` 存在）
   - 🌍 **对非GPF项目完全透明**，不影响其他项目

2. **智能检测范围**：
   - 主要针对 `.worktrees/` 目录下的分支
   - 根目录的开发分支（如develop、main）不受限制
   - 只有Epic分支（以`-e`结尾，非`-ef`）会被阻止直接提交

**开发流程控制：**
```bash
# ❌ 这会被阻止（在Epic分支直接提交）
git checkout epic-auth-e
echo "some changes" > file.txt
git add file.txt
git commit -m "direct commit"  # 被pre-commit hook阻止

# ✅ 正确的开发流程
gpf start -ef login auth        # 创建Feature分支
echo "some changes" > file.txt
git add file.txt
git commit -m "implement login" # 允许提交

# 然后将Feature合并到Epic
git checkout epic-auth-e
git merge epic-auth-e-login-ef    # 允许合并
```

**Hook错误示例：**
```
❌ GPF Policy Violation: Direct commits to Epic branches are not allowed

Current branch: epic-auth-e
Branch type: Epic branch (ends with -e)

💡 Solution: Create a Feature branch for development:

  # 创建Feature分支进行开发：
  git checkout -b epic-auth-e-<feature-name>-ef

  # 或使用GPF命令：
  gpf start -ef <feature-name> auth

GPF开发规则：
  • Epic分支 (-e)：仅用于整合Feature分支
  • Feature分支 (-ef)：实际开发工作
  • 开发流程：Feature → Epic → Develop
```

**管理hooks：**
```bash
# 卸载hooks
./scripts/install-hooks.sh --uninstall

# 重新安装hooks
./scripts/install-hooks.sh

# 查看hooks帮助
./scripts/install-hooks.sh --help
```

### GPF工作目录配置

```bash
# 在项目根目录初始化GPF
cd your-project
gpf config init

# 配置默认分支
gpf config set base-branch main  # 或 develop

# 安装开发流程控制hooks
./scripts/install-hooks.sh
```

## 🐛 故障排查

### 常见问题

#### 1. GitHub CLI未找到
```bash
# 错误：command not found: gh
# 解决方案：
which gh  # 检查gh是否在PATH中
echo $PATH  # 检查PATH配置
```

#### 2. GitHub认证失败
```bash
# 错误：authentication failed
# 解决方案：
gh auth logout
gh auth login --web  # 使用Web认证
```

#### 3. 权限错误
```bash
# 错误：Permission denied
# 解决方案：
sudo chown -R $(whoami) /usr/local/bin/gpf
chmod +x /usr/local/bin/gpf
```

#### 4. GPF命令无响应
```bash
# 检查安装
ls -la /usr/local/bin/gpf
file /usr/local/bin/gpf

# 检查依赖
gpf --debug status
```

### 卸载指南

如需卸载GPF：

```bash
# 卸载GPF
sudo rm -f /usr/local/bin/gpf

# 可选：卸载GitHub CLI
# macOS: brew uninstall gh
# Ubuntu: sudo apt remove gh
# 其他系统请参考对应包管理器文档
```

## 🔄 升级指南

### 升级GPF

```bash
# 自动升级（如果支持）
gpf update

# 手动升级
cd git-pr-cli
git pull origin main
./scripts/install-gpf.sh
```

### 升级GitHub CLI

```bash
# macOS
brew upgrade gh

# Ubuntu/Debian
sudo apt update && sudo apt upgrade gh

# 其他系统请参考对应包管理器
```

## 🏢 企业环境配置

### 企业GitHub/代理配置

```bash
# 配置企业GitHub
export GITHUB_HOST=github.your-company.com
gh config set -h github.your-company.com git_protocol https

# 配置代理
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
gh config set http_proxy $HTTP_PROXY
```

### 批量部署

对于团队批量部署，可以使用以下脚本：

```bash
# 创建团队安装脚本
cat > deploy-gpf-team.sh << 'EOF'
#!/bin/bash
# 团队GPF部署脚本
curl -fsSL https://your-repo/install.sh | bash
gh auth login --hostname github.your-company.com
gpf config set base-branch develop
EOF

chmod +x deploy-gpf-team.sh
```

---

## 🆘 获取帮助

如果遇到安装问题：

1. **查看详细日志**：`gpf --debug status`
2. **检查系统兼容性**：`./scripts/check-compatibility.sh`
3. **提交问题**：[GitHub Issues](https://github.com/your-repo/git-pr-cli/issues)
4. **社区支持**：[讨论区](https://github.com/your-repo/git-pr-cli/discussions)

**成功安装后，请参考 [命令详细文档](COMMANDS.md) 开始使用GPF！**