# Git PR Flow (GPF)

> 🚀 **自然产出高质量PR的命令行工具**  
> 让大功能开发不再困难，享受并行开发的乐趣

[![Version](https://img.shields.io/badge/version-0.1.0--mvp-blue)](#) [![License](https://img.shields.io/badge/license-MIT-green)](#)

## 🎯 核心价值

**解决大功能开发的3大痛点：**
- 🔍 **巨型PR难审查** → 受控拆分，策略性提交
- 🔗 **依赖管理混乱** → 智能依赖检测和同步
- 🔄 **频繁分支切换** → 并行工作树，零上下文切换

**一句话总结：** *让你能够并行开发多个子功能，在合适的时机组合提交高质量PR*

## ⚡ 快速开始

### 安装
```bash
curl -fsSL https://github.com/chatterzhao/git-pr-flow/install.sh | bash
```

### 30秒体验
```bash
# 1. 初始化用户认证系统开发
gpf init user-auth develop

# 2. 并行开发多个子功能
gpf start user-auth/login      # 独立环境开发登录
gpf start user-auth/register   # 独立环境开发注册

# 3. 策略性提交PR
gpf ready user-auth/login && gpf pr user-auth/login    # 基础功能先提交
gpf ready user-auth/register && gpf pr user-auth/register  # 依赖功能后提交
```

## 🏗️ 核心概念

### Epic三层架构
```
develop (主分支)
   ↓
epic/user-auth (功能集成分支)
   ↓
user-auth/login, user-auth/register... (子功能分支)
```

### 并行工作树
```
项目根目录/
├── .worktrees/
│   ├── epic--user-auth/           # Epic集成环境
│   ├── epic--user-auth--login/    # 登录独立环境
│   └── epic--user-auth--register/ # 注册独立环境
└── 你的项目文件...
```

> 💡 **为什么目录是并列的不是嵌套的？**  
> 这是Git worktree的特性，每个worktree都是独立的工作空间，不是文件夹的包含关系

## 🔄 工作流对比

### ❌ 传统方式的问题

**巨型PR模式：**
```bash
git checkout -b feature/user-auth
# ... 开发3周，2000行代码 ...
git commit -m "完整用户认证系统"  # 审查者崩溃
```

**频繁小PR模式：**
```bash
Day 1: PR#1 auth/login
Day 3: PR#2 auth/register (依赖PR#1，但PR#1还在审查)
Day 5: PR#3 auth/login-fix (又一个登录PR...)
Day 7: PR#4 auth/2fa (依赖PR#2，但PR#2还在修改)
```

### ✅ GPF受控并行模式

```bash
# Week 1: 并行开发，独立环境
gpf start user-auth/login      # 在 .worktrees/epic--user-auth--login 开发
gpf start user-auth/register   # 在 .worktrees/epic--user-auth--register 开发
gpf start user-auth/2fa        # 在 .worktrees/epic--user-auth--2fa 开发

# Week 2: 策略性提交
gpf pr user-auth/login         # 基础功能稳定后提交
# 继续开发其他功能...

# Week 3: 有序提交
gpf pr user-auth/register      # 登录稳定后提交注册
gpf pr user-auth/2fa          # 注册稳定后提交2FA
```

**关键优势：**
- 🔄 **并行开发**：多个子功能同时开发，提高效率
- 🎯 **受控节奏**：选择合适时机提交，不再被动
- 📋 **依赖清晰**：自动管理功能间依赖关系
- 🔍 **审查友好**：每个PR都是完整且独立的功能

## 📚 学习路径

### 🚀 5分钟快速上手
阅读本README了解核心概念，跟着快速开始体验基本流程

### 📖 完整学习指南  
👉 **[用户使用指南 →](USER_GUIDELINE.md)**
- 详细的分步教程
- 每个命令的执行效果展示
- 常见问题和解决方案
- 最佳实践建议

### 🔧 深入了解
- **[API文档](API.md)** - 所有命令的详细说明
- **[架构设计](ARCHITECTURE.md)** - 技术实现原理
- **[开发指南](DEVELOPMENT.md)** - 贡献代码指南

## 🎉 为什么选择GPF？

✅ **零学习成本** - 基于熟悉的Git操作，5分钟上手  
✅ **AI友好设计** - 非交互式模式，LLM可直接调用  
✅ **VS Code集成** - 自动分支切换，Git面板显示当前功能变更  
✅ **团队协作** - 清晰的依赖关系，透明的开发进度  
✅ **质量保证** - 内置质量门禁，确保PR质量  

## 🤝 社区与支持

- 🐛 **问题反馈**: [GitHub Issues](https://github.com/chatterzhao/git-pr-flow/issues)
- 💡 **功能建议**: [GitHub Discussions](https://github.com/chatterzhao/git-pr-flow/discussions)
- 📖 **详细文档**: [完整使用指南](USER_GUIDELINE.md)

---

**🚀 开始你的第一个Epic：**
```bash
gpf init your-feature-name develop
```

*5分钟后，你就能体验到高质量PR开发的全新方式！*