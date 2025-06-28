# Git PR Flow 完整使用指南

> 🎯 **从零开始的详细教程** - 让你真正掌握高质量PR开发方式

## 📋 准备工作

### 🔧 环境要求
- Git 2.15+ (支持 `git worktree` 命令)
- Bash 4.0+ 
- 任何Git项目 (新项目或现有项目都可以)

### 📦 安装GPF
```bash
curl -fsSL https://github.com/chatterzhao/git-pr-flow/install.sh | bash

# 验证安装
gpf --version  # 或 git-pr-flow --version
```

## 🎓 核心概念科普

### 🏗️ Git Worktree 是什么？

**传统Git只有一个工作目录：**
```
项目根目录/  ← 只能同时在一个分支工作
├── src/
├── docs/
└── .git/
```

**Git Worktree让你有多个工作目录：**
```
项目根目录/
├── src/
├── docs/
├── .git/
└── .worktrees/
    ├── epic--user-auth/         ← epic/user-auth 分支的工作目录
    ├── epic--user-auth--login/  ← user-auth/login 分支的工作目录
    └── epic--user-auth--register/ ← user-auth/register 分支的工作目录
```

> 💡 **为什么目录是并列的不是嵌套的？**  
> 每个worktree都是独立的Git工作空间，就像独立的项目副本，不是文件夹的包含关系。这样你可以同时在多个分支工作而不需要切换。

### 🌳 Git分支命名限制

**Git有一个重要限制：分支名不能是另一个分支名的前缀**

```bash
❌ 这样会冲突：
epic/user-auth        # 父分支
epic/user-auth/login  # 子分支 - Git禁止！

✅ GPF的解决方案：
epic/user-auth        # Epic集成分支
user-auth/login       # 子功能分支 (去掉epic/前缀)
user-auth/register    # 子功能分支
```

> 🔍 **这是Git的引用规则限制**  
> Git将分支存储为引用（refs），路径 `refs/heads/epic/user-auth` 不能与 `refs/heads/epic/user-auth/login` 共存，因为前者是后者的父路径。

### 🎯 Epic三层架构

**🏗️ 架构层次说明：**
```
develop (基础分支)
   ↓ gpf init user-auth develop
epic/user-auth (Epic集成分支) → .worktrees/epic--user-auth/
   ↓ gpf start user-auth/login
user-auth/login (子功能分支) → .worktrees/user-auth--login/
user-auth/register (子功能分支) → .worktrees/user-auth--register/
```

**💡 关键理解：**
- **Epic分支**：作为集成测试环境，包含完整项目代码
- **子功能分支**：基于Epic分支，专注单一功能开发
- **目录对应**：每个分支都有独立的工作目录，支持并行开发

### 📈 Epic完整生命周期

**🔄 标准Epic工作流：**
```
1️⃣ gpf init user-auth develop
   ↓ 创建Epic集成环境
   🔧 epic/user-auth分支 + .worktrees/epic--user-auth/目录

2️⃣ gpf start user-auth/login
   ↓ 开始第一个子功能
   🌿 user-auth/login分支 + .worktrees/user-auth--login/目录

3️⃣ 正常开发 (git add, commit, push)
   ↓ 功能开发完成
   ✅ 子功能代码就绪

4️⃣ gpf ready 或 gpf pr user-auth/login
   ↓ 创建PR集成到Epic
   🔀 user-auth/login → epic/user-auth

5️⃣ gpf start user-auth/register
   ↓ 开始第二个子功能（基于已集成的Epic）
   🌿 继承login功能，开发register功能

6️⃣ 重复步骤3-4，完成所有子功能

7️⃣ gpf ready (Epic级别)
   ↓ Epic完整功能测试通过
   🚀 epic/user-auth → develop (最终集成)

8️⃣ gpf clean
   ↓ 清理已合并的分支和worktree
   🧹 释放磁盘空间
```

**🎯 Epic的核心价值：**
- **并行开发**：多个子功能可以同时进行
- **渐进集成**：子功能逐步集成到Epic环境测试
- **风险控制**：Epic作为缓冲层，避免直接污染主分支
- **完整测试**：Epic环境提供真实的集成测试场景

## 📖 完整实战教程

我们以开发**用户认证系统**为例，演示完整的GPF工作流：
- 🔐 基础登录功能
- 📝 用户注册功能  
- 🔐 双因子认证
- 🌐 社交登录集成

### 🚀 第1步：初始化Epic开发环境

```bash
# 切换到你的项目目录
cd your-project

# 初始化用户认证系统开发
gpf init user-auth develop
```

**📝 命令参数说明：**
- `user-auth`：Epic名称，系统会自动创建 `epic/user-auth` 分支
- `develop`：基础分支，Epic将基于此分支创建
- **自动命名规则**：
  - Git分支：`epic/user-auth` （系统自动添加epic/前缀）
  - Worktree目录：`.worktrees/epic--user-auth` （/替换为--，因为目录名不支持/字符）

**这时会发生什么：**
```
▶ 初始化功能开发环境

🔍 检测已有配置，会询问是否用已有配置还是更新配置...
ℹ 未发现或更新配置文件，开始新配置

? 功能描述: 用户认证系统

🔍 检测项目已有git分支...
  发现分支: main, develop, staging

? 选择基于哪个分支创建 auth 分支: (方向键选择)
  ❯ develop (开发主分支) ⭐ 推荐
  ├─ main (生产稳定分支)
  ├─ staging (预发布分支)
  └─ 自定义分支...(要存在的分支名)
```

**你要做的：**
- 用方向键选择一个基础分支（通常选择推荐的）
- 按回车确认

**结果：**
- ✅ 创建了 `epic/user-auth` 分支（基于develop）
- ✅ 创建了 `.worktrees/epic--user-auth/` 工作目录（包含完整项目代码）
- ✅ 生成了 `.git-pr-flow.yaml` 配置文件
- ✅ 设置了独立的Epic集成测试环境

**📁 目录结构变化：**
```
项目根目录/
├── .git/
├── .worktrees/
│   └── epic--user-auth/           ← Epic工作目录
│       ├── src/                   ← 完整项目代码
│       ├── docs/
│       ├── .git-pr-flow.yaml     ← Epic配置
│       └── ...（所有项目文件）
└── ...（原项目文件）
```

### 第3步：开始第一个子功能

```bash
gpf start auth/login # 如果只有 start 没有后面参数，则会列出所有子功能（子分支）
```

**这时会发生什么：**
```
🔍 分析子功能: auth/login
  ✔ 检测到功能: auth (已存在)
  ✔ 工作树环境: .worktrees/auth--login
  ✔ 这是第一个子功能

? 依赖关系: (方向键选择)
  ❯ 无依赖 (基础功能)
  ├─ 依赖 develop (直接基于基础分支)
  └─ 查看Epic状态

? 确认配置:
  子功能: auth/login  
  功能组: auth
  依赖: 无 (基础功能)
  工作环境: .worktrees/auth--register
  [Y/n] 
```

**你要做的：**
- 选择依赖关系（第一个子功能通常选"无依赖"）
- 确认配置

**结果：**
- 自动切换到独立的工作环境
- 可以专注开发登录功能

**注意：**
由于我们使用了 worktrees，所以你随时可以 cd 进入另一个工作环境，传统cd 方式 或 gpf start auth/register。

### 第4步：正常开发第一个功能

```bash
# 现在你在 .worktrees/auth--login 目录中
# 正常开发，正常提交

echo "实现登录功能" > src/auth/login.js
git add .
git commit -m "feat: 实现基础登录功能"

echo "添加密码验证" >> src/auth/login.js  
git add .
git commit -m "feat: 添加密码强度验证"

# 继续开发...
```

### 第5步：开始第二个子功能

```bash
gpf start auth/register
```

**这时会发生什么：**
```
🔍 分析子功能: auth/register
  ✔ 检测到功能: auth (已存在)
  ✔ 工作树环境: .worktrees/auth--login
  ⚠ 检测到相关分支: auth/login

? 依赖关系: (方向键选择)
  ❯ 依赖 auth/login (推荐，基于代码分析)
  ├─ 无依赖 (独立开发)
  ├─ 查看 auth/login 详情...
  └─ 手动指定其他依赖
```

**你要做的：**
- 通常选择推荐的依赖关系
- 确认配置

**结果：**
- 自动继承 auth/login 的所有代码
- 可以在此基础上开发注册功能

### 第6步：查看整体进度

```bash
git-pr-flow status
```

**你会看到：**
```
🚀 [Epic] 用户认证系统 - 总体进度: 45%

📊 分支架构状态:
develop (基础线) ← 配置的基分支
  ↑ 
epic/auth (集成线) - 准备集成2个子功能
  ↑ ↑
  ├─ ✅ auth/login (开发完成，3个提交) 
  └─ 🔄 auth/register (开发中，1个提交)

🔄 同步状态:
  ├─ epic/auth: 与 develop 同步 ✓
  ├─ auth/login: 准备集成到Epic
  └─ auth/register: 基于 auth/login ✓

💡 建议操作:
  1. auth/login 可以集成到Epic
  2. 继续开发 auth/register
```

**含义：**
- 一目了然的开发进度
- 清晰的分支关系
- 智能的操作建议

### 第7步：同步更新

当某个子功能开发完成，其他分支想获取更新：

```bash
git-pr-flow sync
```

**这时会发生什么：**
```
🔍 分析功能同步需求...

📊 当前状态:
├─ 基础分支: develop (GitFlow策略)
├─ epic/auth (集成分支) - 与 develop 同步
├─ auth/login (已完成) - 3个提交，准备集成
└─ auth/register (开发中) - 基于旧版 auth/login

🔄 建议同步路径:
  1️⃣ auth/login → epic/auth (新功能集成)
  2️⃣ epic/auth → auth/register (获取login更新)

? 同步策略: (方向键选择)
  ❯ 智能同步 (通过Epic分支安全传播)
  ├─ 仅集成login (不更新其他分支)
  ├─ 查看变更详情...
  └─ 暂不同步
```

**你要做的：**
- 选择同步策略（通常选智能同步）
- 如果有冲突，按提示解决

**结果：**
- 所有分支获得最新的更新
- 及时发现和解决冲突

### 第8步：创建PR

当某个子功能稳定时：

```bash
git-pr-flow pr auth/login
```

**这时会发生什么：**
```
🎯 分析PR上下文...

📋 检测到信息:
├─ Epic: 用户认证系统 (epic/auth)
├─ 当前子功能: 01/04 - 基础登录
├─ 依赖关系: develop → epic/auth → auth/login
├─ 变更文件: 3个文件，+156/-0行
└─ 测试覆盖: 新增12个测试用例

✨ 自动生成PR描述:

┌─────────────────────────────────────────────┐
│ ## 🎯 Epic: 用户认证系统                      │
│ **当前部分**: 01/04 - 基础登录功能             │
│                                           │
│ ## 📋 功能全景                              │
│ ```                                      │
│ ┌─ 01-基础登录 ◄ 当前PR                     │
│ ├─ 02-用户注册 🔄 开发中                   │
│ ├─ 03-双因子认证 💻 计划中                  │  
│ └─ 04-社交登录 ⏳ 待开始                   │
│ ```                                      │
│ [...]                                    │
└─────────────────────────────────────────────┘

? PR配置: (方向键选择)
  ❯ 立即创建PR (epic/auth ← auth/login)
  ├─ 编辑描述后创建
  ├─ 保存为模板
  └─ 暂不创建
```

**你要做的：**
- 选择是否立即创建或编辑描述
- 确认创建

**结果：**
- 自动创建包含完整上下文的PR
- 审查者能清楚了解这个PR在整个功能中的位置

### 第9步：策略性发布规划

当多个子功能都开发完成：

```bash
git-pr-flow ready
```

**这时会发生什么：**
```
🎯 分析Epic级PR提交策略...

📊 Epic状态分析:
[Epic] 用户认证系统 - 当前完成度: 75%
├─ epic/auth: 集成健康度 95% ✅
├─ 功能完整性: 核心功能已就绪 ✅  
├─ 测试覆盖率: 89% (目标85%) ✅
└─ 文档完整性: 待补充 ⚠️

💡 建议的提交策略:

📝 Strategy A: 渐进式发布
  Week 1: auth/register → epic/auth (扩展功能)
  Week 2: 完成 auth/2fa 开发
  Week 3: auth/2fa → epic/auth
  Week 4: epic/auth → develop (阶段性发布)

🚀 Strategy B: 等待完整发布  
  完成所有4个子功能 → epic/auth → develop
  优势: 用户体验完整，功能完备
  
⚡ Strategy C: 核心功能先发布
  当前核心功能(login+register) → develop
  高级功能(2fa+social)单独规划

? 选择提交策略: (方向键选择)
  ❯ 策略A - 渐进式发布 (持续交付)
  ├─ 策略B - 等待完整发布 (完整体验)
  ├─ 策略C - 核心功能先发布 (快速价值)
  └─ 查看Epic集成测试报告
```

**你要做的：**
- 根据项目需求选择发布策略
- 按建议执行后续操作

**结果：**
- 有策略地控制PR提交时机
- 平衡开发速度和审查质量

## 📋 分支与目录对应规则

### 🎯 核心设计原则：零心智负担

Git PR Flow 使用简单的转换规则，让你看到分支名立即知道工作目录位置：

**🔥 Epic分支命名规则：**
| 命令 | Git分支 | Worktree目录 | 说明 |
|------|---------|-------------|------|
| `gpf init user-auth develop` | `epic/user-auth` | `.worktrees/epic--user-auth` | Epic集成分支（自动添加epic/前缀） |
| `gpf start auth/login` | `auth/login` | `.worktrees/auth--login` | 子功能分支 |
| `gpf start auth/register` | `auth/register` | `.worktrees/auth--register` | 子功能分支 |

**📐 核心转换规则：**
1. **Epic前缀自动添加**：`gpf init xx` → 分支 `epic/xx`
2. **目录名转换**：分支名中的 `/` 替换为目录名中的 `--`
3. **文件系统兼容**：所有操作系统都支持 `--` 字符

**为什么使用双横线？**
- ✅ 所有操作系统文件系统都支持
- ✅ 不会与Shell命令冲突  
- ✅ Git分支命名完全兼容
- ✅ 简单机械转换，无需记忆

### 💡 VS Code集成建议

**方案1: 多窗口开发** (推荐)
```bash
# 为每个主要Epic开启独立VS Code窗口
code /path/to/.worktrees/auth--login     # 认证功能窗口
code /path/to/.worktrees/payment--api    # 支付功能窗口
```

**方案2: Workspace配置**
```json
// .vscode/multi-epic.code-workspace
{
  "folders": [
    {"path": ".worktrees/auth--login"},
    {"path": ".worktrees/payment--api"},
    {"path": "."}  // 主项目作为参考
  ]
}
```

**方案3: 推荐扩展**
- 安装 `Git Worktree` 扩展 (PhilStainer.git-worktree)
- 安装 `Git Worktrees` 扩展 (GitWorktrees.git-worktrees)
- 提供统一的worktree管理界面

## 🔄 日常使用技巧

### 每天开始工作

```bash
# 1. 查看当前状态
git-pr-flow status

# 2. 同步最新更新
git-pr-flow sync

# 3. 继续开发
# 正常的 git add, commit, push...
```

### 快速切换子功能

```bash
# 所有子功能都在同一个工作树中
# 直接用 git checkout 切换即可

git checkout auth/login     # 开发登录功能
git checkout auth/register  # 开发注册功能  
git checkout auth/2fa       # 开发2FA功能
```

### 处理冲突

当同步时遇到冲突：
```bash
# 系统会自动检测并引导你解决
? 解决方式: (方向键选择)
  ❯ 手动编辑 (推荐)
  ├─ 使用我的版本
  ├─ 使用他们的版本
  ├─ 智能合并
  └─ 跳过此文件

# 选择"手动编辑"会自动打开编辑器
# 解决冲突后保存文件即可
```

### 清理工作环境

```bash
# 定期清理已合并的分支
git-pr-flow clean

# 系统会智能识别可清理的内容
? 清理策略: (方向键选择)
  ❯ 智能清理 (已合并分支)
  ├─ 选择性清理...
  ├─ 查看磁盘占用...
  └─ 取消操作
```

## 💡 最佳实践

### 1. 功能拆分建议

**好的拆分：**
- `auth/login` - 基础登录
- `auth/register` - 用户注册
- `auth/2fa` - 双因子认证
- `auth/social` - 社交登录

**避免的拆分：**
- `auth/part1`, `auth/part2` - 没有功能语义
- `auth/fix-bug` - 应该在对应功能分支中修复

### 2. 依赖关系设计

**推荐：**
```
login (基础) → register (依赖login)
                ↓
              2fa (依赖register)
              
login → social (依赖login，但不依赖register)
```

**避免：**
```
login → register → social → 2fa (过长的依赖链)
```

### 3. PR提交时机

**渐进式发布适用于：**
- 功能可以分阶段上线
- 希望尽早获得用户反馈
- 团队倾向于持续交付

**整合式发布适用于：**
- 功能必须完整才能发布
- 用户体验要求高
- 功能间耦合度较高

### 4. 团队协作

**Epic负责人：**
- 制定功能拆分方案
- 决定PR提交策略
- 协调冲突解决

**功能开发者：**
- 专注自己的子功能开发
- 及时同步依赖更新
- 配合Epic集成测试

## 🆘 常见问题

### Q: 如何在已有分支上使用？

```bash
# 如果已经有功能分支，可以迁移到Epic模式
git checkout existing-branch
gpf init auth
gpf start auth/existing --existing
```

### Q: 忘记当前在哪个分支？

```bash
# 随时查看状态
git-pr-flow status

# 会显示当前分支和整体进度
```

### Q: 如何撤销操作？

```bash
# Git PR Flow 不会破坏你的代码
# 所有操作都是标准的Git操作
# 可以用标准Git命令撤销

git checkout main  # 回到主分支
git branch -D unwanted-branch  # 删除不需要的分支
```

### Q: 工作树占用空间太大？

```bash
# 定期清理
git-pr-flow clean

# 设置自动清理
git-pr-flow config set sync.cleanup_policy auto
```

### Q: 团队成员不熟悉怎么办？

```bash
# 使用交互式教程
git-pr-flow help tutorial

# 查看快速参考
git-pr-flow help quickstart
```

## 🎯 总结

使用 Git PR Flow，你可以：

✅ **高质量PR** - 自动生成完整上下文，审查者容易理解  
✅ **并行开发** - 多个子功能同时开发，互不阻塞  
✅ **受控节奏** - 策略性选择PR时机，不再被动频繁提交  
✅ **简单操作** - 交互式设计，无需记忆复杂参数  
✅ **团队协作** - 清晰的依赖关系，透明的开发进度  

**开始你的第一个Epic：**
```bash
gpf init your-feature-name
```

5分钟后，你就能体验到高质量PR开发的全新方式！