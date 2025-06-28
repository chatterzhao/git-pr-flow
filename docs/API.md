# Git PR Flow API 参考

> 完整命令行接口文档 - 面向使用者

## 快速导航

- 📖 **[项目介绍](README.md)** - 了解项目目标和核心价值
- 🔧 **[开发指南](DEVELOPMENT.md)** - 贡献代码和开发环境  
- 🏗️ **[架构设计](ARCHITECTURE.md)** - 系统架构和模块设计
- 🎨 **[交互设计](UX.md)** - 用户体验设计

## 命令行接口

### 核心命令

#### `gpf init`
初始化功能开发环境

**语法**:
```bash
gpf init [功能名称]
```

**无参数使用** (列出现有功能):
```bash
$ gpf init

📋 检测到的现有功能配置:

🔍 已有Epic配置:
├─ auth (用户认证系统) - 创建于2天前
│   └─ 基础分支: develop, 工作树: .worktrees/auth--*
├─ payment (支付系统) - 创建于1周前  
│   └─ 基础分支: main, 工作树: .worktrees/payment--*
└─ dashboard (管理面板) - 创建于3天前
    └─ 基础分支: develop, 工作树: .worktrees/dashboard--*

? 选择操作: (方向键选择)
  ❯ 创建新的Epic功能
  ├─ 重新配置 auth 
  ├─ 重新配置 payment
  ├─ 重新配置 dashboard
  └─ 查看Epic详情

选择：创建新的Epic功能

? 新Epic名称: user-profile
? Epic描述: 用户个人资料管理

# ... 继续正常初始化流程
```

**智能配置复用初始化**:
```bash
$ gpf init auth

▶ 初始化功能开发环境

🔍 检测已有配置...
✔ 发现配置文件: .git-pr-flow.yaml
✔ Epic配置: auth (用户认证系统)

📋 已有配置信息:
├─ Epic名称: auth (用户认证系统)
├─ 基础分支: develop  
├─ 架构类型: 完整架构
├─ 工作树路径: .worktrees/auth--login (示例)
├─ 上次配置: 2天前
└─ 配置版本: v1.0

? 使用已有配置? (方向键选择)
  ❯ 是，使用已有配置 (快速启动)
  ├─ 否，重新配置所有选项
  ├─ 部分修改 (仅修改基础分支等)
  ├─ 查看配置详情
  └─ 删除配置重新开始

选择：是，使用已有配置

▶ 验证环境...
✔ 基础分支 develop 存在且健康
✔ Epic分支 epic/auth 存在 
✔ 工作树路径可用
✔ 配置兼容性检查通过

✔ 功能环境就绪 (基于已有配置)
💡 架构: develop ← epic/auth ← features
ℹ 使用 'gpf start' 开始子功能开发
```

**首次配置流程** (无配置文件时):
```bash
$ gpf init auth

🔍 检测已有配置...
ℹ 未发现配置文件，开始新配置

▶ 初始化功能开发环境
? 功能描述: 用户认证系统

🔍 检测项目分支结构...
  发现分支: main, develop, staging, release/v2.0

? 基础分支选择: (方向键选择)
  ❯ develop (开发主分支) ⭐ 推荐
  ├─ main (生产稳定分支)
  ├─ staging (预发布分支)
  ├─ release/v2.0 (发布分支)
  ├─ 自定义分支...
  └─ 查看分支详情

# ... 继续正常配置流程 ...

✔ 配置完成，已保存到 .git-pr-flow.yaml
💡 下次使用 'gpf init auth' 将直接复用此配置
```

**配置文件格式**:
```yaml
# .git-pr-flow.yaml  
epic_name: auth
description: 用户认证系统
base_branch: develop
architecture: complete
epic_branch: epic/auth
worktree_path: .worktrees/auth--login
workflow_type: gitflow
created_at: 2024-01-01T10:00:00Z
config_version: "1.0"
```

**自定义分支示例**:
```bash
选择：自定义分支...
? 输入基础分支名: release/v3.0

▶ 验证分支...
✔ 分支 release/v3.0 存在
✔ 分支状态健康

? 确认基于 release/v3.0 创建Epic? [Y/n] Y

▶ 创建架构...
✔ 创建Epic分支: epic/auth (基于 release/v3.0)
💡 架构说明:
  release/v3.0 (基础线) ← epic/auth (集成线) ← features (开发线)
```

**核心理念体现**：
- 💾 **智能配置复用** - 自动检测和复用已有配置，避免重复设置
- 🔀 **灵活的基分支支持** - 适配不同团队的分支策略 (GitFlow/GitHubFlow/自定义)
- 🏗️ **Epic分支集成** - 在任何基分支上构建功能完整性保证
- 🏠 **独立开发环境** - 避免分支切换，支持并行开发
- 🎯 **受控PR节奏** - 为策略性提交做准备

---

#### `gpf start`
开始新的子功能开发 (含自动分支切换)

**语法**:
```bash
gpf start [子功能名] [选项]
```

**新功能**: 自动分支切换
- 主仓库自动切换到对应的功能分支
- 使VS Code Git面板显示当前功能的文件变更
- 解决worktree环境下的Git可视化问题

**无参数使用** (列出现有子功能):
```bash
$ gpf start

🔍 检测当前Epic环境: auth (用户认证系统)
📋 现有子功能分支:

✅ 已完成:
├─ auth/login (3个提交) - 最后更新: 2小时前
└─ auth/register (5个提交) - 最后更新: 1小时前

🔄 开发中:
├─ auth/2fa (2个提交) - 最后更新: 30分钟前
└─ auth/social (1个提交) - 最后更新: 1天前

? 选择操作: (方向键选择)
  ❯ 创建新的子功能
  ├─ 切换到 auth/login
  ├─ 切换到 auth/register  
  ├─ 切换到 auth/2fa
  ├─ 切换到 auth/social
  ├─ 查看分支详情...
  └─ 切换到其他Epic

选择：创建新的子功能

? 子功能名称: auth/oauth
? 功能描述: OAuth第三方登录集成

# ... 继续正常创建流程
```

**智能交互式设计**:
```bash
$ gpf start auth/register

🔍 分析子功能: auth/register
  ✔ 检测到功能: auth (已存在)
  ✔ 工作树环境: .worktrees/auth--login
  ⚠ 检测到相关分支: auth/login

? 依赖关系: (方向键选择)
  ❯ 依赖 auth/login (推荐，基于代码分析)
  ├─ 依赖 main (独立开发)
  ├─ 查看 auth/login 详情...
  └─ 手动指定其他依赖

? 确认配置:
  子功能: auth/register  
  功能组: auth
  依赖: auth/login
  工作环境: .worktrees/auth--register (基于login分支)
  [Y/n] Y

✔ 子功能环境就绪
ℹ 在 .worktrees/auth--register 中开发，专注于注册功能

💡 VS Code集成提示:
  git-pr-flow code auth/register  # 在VS Code中打开此功能
  git-pr-flow workspace           # 生成多Epic工作区配置

🔄 自动分支切换:
  主仓库自动切换到 auth/register 分支 (如果可用)
  便于VS Code Git面板显示当前功能的文件变更
```

**核心理念体现**：
- 🏠 使用独立工作环境，无分支切换成本
- 🔗 智能检测依赖关系，保持逻辑清晰
- 🎯 为受控的PR节奏做准备

---

#### `git-pr-flow status`
功能开发进度仪表盘

**语法**:
```bash
git-pr-flow status
```

**Epic进度仪表盘**:
```bash
$ git-pr-flow status

🚀 [Epic] 用户认证系统 - 总体进度: 67%

📊 分支架构状态:
develop (基础线) ← 配置的基分支
  ↑ 
epic/auth (集成线) - 3个子功能已集成
  ↑ ↑ ↑
  ├─ ✅ auth/login (已完成) 
  ├─ 🔄 auth/register (审核中，PR#124)
  └─ 💻 auth/2fa (开发中)

🔄 同步状态:
  ├─ epic/auth: 领先 develop 5个提交
  ├─ auth/login: 已同步到Epic ✓
  ├─ auth/register: 基于Epic最新版本 ✓
  └─ auth/2fa: 需要同步Epic更新 ⚠️

💡 建议操作:
  1. auth/2fa 需要同步最新更新
  2. auth/register PR#124 可以合并
  3. Epic准备度: 可考虑向 develop 提交

? 查看详情: (方向键选择)
  ❯ Epic分支详细信息
  ├─ 分支架构配置
  ├─ 三层架构依赖图  
  ├─ 子功能开发timeline
  ├─ PR策略建议
  └─ 工作树环境状态
```

**分支架构配置详情**:
```bash
选择：分支架构配置

📋 当前Epic配置:
├─ Epic名称: auth (用户认证系统)
├─ 基础分支: develop
├─ Epic分支: epic/auth
├─ 工作树路径: .worktrees/auth--login (示例)
├─ 创建时间: 3天前
└─ 最后同步: 2小时前

🔄 分支策略:
├─ 基础分支策略: GitFlow (develop-based)
├─ Epic合并目标: develop
├─ 子功能合并目标: epic/auth
└─ 最终发布路径: develop → main

? 配置操作: (方向键选择)
  ❯ 查看基础分支状态
  ├─ 切换基础分支 (高级操作)
  ├─ 更新Epic描述
  └─ 返回状态概览
```

**进度可视化详情**:
```bash
选择：Epic分支详细信息

📈 Epic集成状态详情:

功能完整性分析:
┌─────────────────────────────────────┐
│ auth/login    ████████████ 100%    │
│ auth/register ████████▒▒▒▒ 80%     │  
│ auth/2fa     ████▒▒▒▒▒▒▒▒ 40%     │
└─────────────────────────────────────┘

Epic健康度:
├─ ✅ 集成测试通过率: 95%
├─ ⚠️ 代码覆盖率: 78% (目标80%)
├─ ✅ 依赖关系清晰
└─ ✅ 无重大冲突

提交时间线:
Week 1: ████ auth/login 完成
Week 2: ███▒ auth/register 即将完成  
Week 3: █▒▒▒ auth/2fa 持续开发
Week 4: ▒▒▒▒ Epic整合和测试

? 后续操作:
  ❯ 同步auth/2fa更新
  ├─ 查看Epic集成测试报告
  └─ 规划下一步PR策略
```

---

#### `git-pr-flow sync`
智能同步依赖，保持代码最新

**语法**:
```bash
git-pr-flow sync
```

**Epic分支智能同步**:
```bash
$ git-pr-flow sync

🔍 分析功能同步需求...

📊 当前状态:
├─ 基础分支: develop (GitFlow策略)
├─ epic/auth (集成分支) - 2个提交领先 develop
├─ auth/login (已完成) - 准备同步到Epic
├─ auth/register (开发中) - 基于旧版Epic  
└─ auth/2fa (开发中) - 需要login的更新

🔄 建议同步路径:
  1️⃣ auth/login → epic/auth (新功能集成)
  2️⃣ epic/auth → auth/register (获取login更新)
  3️⃣ epic/auth → auth/2fa (获取login更新)
  4️⃣ develop → epic/auth (获取基础分支更新，如需要)

? 同步策略: (方向键选择)
  ❯ 智能同步 (通过Epic分支安全传播)
  ├─ 包含基础分支更新 (先同步develop更新)
  ├─ 直接同步 (跳过Epic，点对点同步)
  ├─ 查看变更详情...
  └─ 暂不同步

选择：包含基础分支更新

▶ 执行完整同步...
[0/4] develop → epic/auth ✔ (基础分支同步)
[1/4] auth/login → epic/auth ✔ (集成测试通过)
[2/4] epic/auth → auth/register ✔ (无冲突)
[3/4] epic/auth → auth/2fa ⚠️ (检测到冲突)

⚠️ 冲突处理: auth/2fa
文件: src/auth/utils.js (函数签名变化)
来源: develop基础更新 + auth/login新功能
? 解决方式:
  ❯ 打开编辑器解决
  ├─ 保留Epic版本 (采用最新设计)
  ├─ 保留本地版本 (保持当前实现)
  └─ 查看冲突详情

🎉 同步完成!
💡 状态更新: 
  - Epic与 develop 保持同步
  - auth功能完整性 +20%

? 后续操作:
  ❯ 继续开发
  ├─ 查看Epic集成测试结果
  └─ 规划向 develop 的PR策略
```

**核心理念体现**：
- 🔀 **基础分支感知** - 自动识别和同步配置的基础分支更新
- 🏗️ **Epic作为中转站** - 通过Epic分支安全传播所有变更
- ⚡ **及时冲突发现** - 在Epic层统一管理和解决冲突
- 🔄 **完整性保证** - 保持Epic与基础分支和子功能的一致性

---

#### `git-pr-flow pr`
**智能PR创建和描述生成**

**语法**:
```bash
git-pr-flow pr [子功能名]
```

**自动PR描述生成**:
```bash
$ git-pr-flow pr auth/register

🎯 分析PR上下文...

📋 检测到信息:
├─ Epic: 用户认证系统 (epic/auth)
├─ 当前子功能: 02/04 - 用户注册
├─ 依赖关系: auth/login → auth/register → auth/2fa
├─ 变更文件: 12个文件，+324/-89行
└─ 测试覆盖: 新增23个测试用例

✨ 自动生成PR描述:

┌─────────────────────────────────────────────┐
│ ## 🎯 Epic: 用户认证系统                      │
│ **当前部分**: 02/04 - 用户注册管理             │
│                                           │
│ ## 📋 功能全景                              │
│ ```                                      │
│ ┌─ 01-用户登录 ✅                          │
│ ├─ 02-用户注册 ◄ 当前PR                    │
│ ├─ 03-双因子认证 ⏳                        │  
│ └─ 04-权限管理 ⏳                          │
│ ```                                      │
│                                           │
│ ## 🔗 依赖关系                              │
│ - 基础分支: develop                        │
│ - 基于: epic/auth                          │
│ - 依赖: auth/login (已合并)                 │
│ - 后续: auth/2fa 将依赖此PR                 │
│                                           │
│ ## ✅ 本PR实现                              │
│ - 用户注册核心逻辑                           │
│ - 邮箱验证机制                              │
│ - 注册表单组件                              │
│ - 相关API端点                              │
│                                           │
│ ## 🧪 测试验证                              │
│ - ✅ 单元测试: 95%覆盖率                     │
│ - ✅ 集成测试: 与Epic分支兼容                 │
│ - ✅ E2E测试: 注册流程完整                    │
│                                           │
│ ## 👀 审查要点                              │
│ - 注册逻辑安全性                             │
│ - 与登录功能的一致性                          │
│ - API设计的扩展性                           │
└─────────────────────────────────────────────┘

? PR配置: (方向键选择)
  ❯ 立即创建PR (epic/auth ← auth/register)
  ├─ 编辑描述后创建
  ├─ 保存为模板
  ├─ 查看提交详情
  └─ 暂不创建

▶ 创建PR...
✔ PR #125 已创建
✔ 自动关联Epic #123
✔ 通知相关开发者
🔗 https://github.com/repo/pull/125

💡 Epic状态更新: 
  - Epic完成度: 50% → 75%  
  - 下一步: auth/2fa 可以开始基于此PR开发
```

**核心理念体现**：
- 🎯 **自动化PR准备** - 零手工编写，智能生成完整上下文
- 🔗 **Epic关联** - 自动关联Epic分支和相关PR
- 📊 **进度追踪** - PR创建自动更新Epic完成度
- ⏰ **受控节奏** - 可选择立即创建或暂存准备

---

#### `git-pr-flow ready`
**Epic级策略性PR提交规划**

**语法**:
```bash
git-pr-flow ready
```

**Epic完整性分析和PR规划**:
```bash
$ git-pr-flow ready

🎯 分析Epic级PR提交策略...

📊 Epic状态分析:
[Epic] 用户认证系统 - 当前完成度: 78%
├─ epic/auth: 集成健康度 95% ✅
├─ 功能完整性: 核心功能已就绪 ✅  
├─ 测试覆盖率: 89% (目标85%) ✅
└─ 文档完整性: 待补充 ⚠️

📋 可提交的子功能和Epic选项:
┌─ 子功能级PR (常规提交)
├─ [✓] auth/login (200行) → epic/auth
├─ [✓] auth/register (180行) → epic/auth  
├─ [◐] auth/2fa (150行，register依赖) → epic/auth
└─ [!] auth/social (220行，冲突) → epic/auth

┌─ Epic级PR (功能整合)  
└─ [✓] epic/auth (完整功能) → main

💡 建议的提交策略:

📝 Strategy A: 渐进式发布
  Week 1: auth/login → epic/auth (基础先行)
  Week 2: auth/register → epic/auth (扩展功能)
  Week 3: 解决auth/social冲突 → epic/auth
  Week 4: epic/auth → main (完整功能发布)

🚀 Strategy B: Epic整合发布  
  完成所有子功能开发 → 直接 epic/auth → main
  优势: 用户体验完整，风险可控
  
⚡ Strategy C: 混合策略
  关键子功能先发布 → 剩余功能Epic发布

? 选择提交策略: (方向键选择)
  ❯ 策略A - 渐进式发布 (持续交付)
  ├─ 策略B - Epic整合发布 (完整体验)
  ├─ 策略C - 混合策略 (平衡风险和速度)
  ├─ 查看Epic集成测试报告
  └─ 暂不提交

▶ 执行策略B - Epic整合发布...
✔ Epic准备检查通过
✔ 生成Epic → main PR
  - 标题: [Epic] 用户认证系统完整实现
  - 描述: 包含4个子功能的完整实现
  - 关联: 关闭Issues #45, #67, #89
  - 里程碑: 用户系统 v2.0

🎉 Epic PR已创建: #126
💡 预期影响: 用户体验大幅提升，安全性增强
```

**核心理念体现**：
- 🏗️ **Epic级思维** - 不仅管理子功能PR，更关注Epic完整性
- ⏰ **受控的发布节奏** - 支持渐进式和整合式两种发布策略
- 🎯 **策略性选择** - 基于Epic健康度和业务需求选择最佳时机
- 📊 **质量保证** - Epic级的集成测试和完整性验证

---

#### `git-pr-flow clean`
清理工作树和分支

#### `git-pr-flow code`
在VS Code中打开指定功能工作树

**语法**:
```bash
git-pr-flow code [功能分支名]
```

**示例**:
```bash
# 在VS Code中打开认证功能开发环境
git-pr-flow code auth/login

# 自动在VS Code中打开对应的worktree目录
# 等同于: code .worktrees/auth--login
```

#### `git-pr-flow workspace`
生成VS Code多Epic工作区配置文件

**语法**:
```bash
git-pr-flow workspace [选项]
```

**示例**:
```bash
# 生成包含所有Epic的工作区文件
git-pr-flow workspace

# 生成指定Epic的工作区
git-pr-flow workspace --epic auth,payment
```

**生成的工作区文件**:
```json
// git-pr-flow.code-workspace
{
  "folders": [
    {"name": "Auth Epic", "path": ".worktrees/auth--login"},
    {"name": "Payment Epic", "path": ".worktrees/payment--api"},
    {"name": "Main Project", "path": "."}
  ],
  "settings": {
    "git.detectSubmodules": false
  }
}
```

**语法**:
```bash
git-pr clean [选项]
```

**选项**:
- `-w, --worktrees` - 清理工作树
- `-b, --branches` - 清理分支
- `-m, --merged` - 只清理已合并的
- `-f, --force` - 强制清理
- `--dry-run` - 预览清理操作

**示例**:
```bash
# 交互式清理
git-pr clean

# 清理已合并分支
git-pr clean -b -m

# 预览清理
git-pr clean --dry-run

# 强制清理所有
git-pr clean -w -b -f
```

**输出**:
```
💾 工作树占用分析:
  @epics/auth     847MB  ├─ auth/login (已合并)
                         ├─ auth/register (已合并) 
                         └─ auth/2fa (活跃)
  @temp/hotfix    156MB  └─ hotfix/bug-123 (已合并)

? 清理选择:
  ❯ 智能清理 (节省 ~650MB)
  ├─ 选择性清理
  ├─ 清理所有已合并
  └─ 取消

✔ 清理完成:
  - 删除 auth/login 工作树
  - 删除 auth/register 工作树  
  - 删除 hotfix/bug-123 工作树
  - 节省磁盘空间: 650MB
```

---

### 辅助命令

#### `git-pr config`
配置管理

**语法**:
```bash
git-pr config <action> [key] [value] [选项]
```

**操作**:
- `get <key>` - 获取配置值
- `set <key> <value>` - 设置配置值
- `unset <key>` - 删除配置
- `list` - 列出所有配置
- `edit` - 编辑配置文件

**选项**:
- `--global` - 全局配置
- `--local` - 项目配置（默认）

**示例**:
```bash
# 查看配置
git-pr config list

# 设置Epic目录
git-pr config set core.epic_dir @epics

# 设置同步策略
git-pr config set sync.default_scope deps

# 编辑配置
git-pr config edit
```

---

#### `git-pr epic`
Epic管理

**语法**:
```bash
git-pr epic <action> [name] [选项]
```

**操作**:
- `create <name>` - 创建Epic
- `list` - 列出Epic
- `switch <name>` - 切换Epic
- `delete <name>` - 删除Epic
- `status <name>` - Epic状态

**示例**:
```bash
# 创建Epic
git-pr epic create payment

# 列出Epic
git-pr epic list

# 切换Epic
git-pr epic switch auth

# Epic状态
git-pr epic status auth
```

---

#### `git-pr deps`
依赖关系管理

**语法**:
```bash
git-pr deps <action> [分支] [选项]
```

**操作**:
- `add <branch> <dependency>` - 添加依赖
- `remove <branch> <dependency>` - 移除依赖
- `list [branch]` - 列出依赖
- `tree [branch]` - 依赖树
- `check` - 检查循环依赖

**示例**:
```bash
# 添加依赖
git-pr deps add auth/register auth/login

# 查看依赖树
git-pr deps tree

# 检查循环依赖
git-pr deps check
```

---

## 配置API

### 配置文件格式

#### 全局配置 (`~/.gitprconfig`)
```ini
[core]
epic_dir = @epics
temp_dir = @temp
default_base = main

[sync]
default_scope = deps
conflict_mode = prompt
cleanup_policy = ask
strategy = merge

[ui]
color = auto
ascii_tree = true
progress = true

[worktree]
auto_cleanup = true
disk_threshold = 1GB
```

#### 项目配置 (`.git/pr-config`)
```ini
[epic "auth"]
description = "用户认证系统"
worktree_path = .worktrees/auth--login

[epic "payment"]
description = "支付系统"
worktree_path = .worktrees/payment--checkout

[branch "auth/login"]
depends = main
epic = auth
ready = true

[branch "auth/register"]
depends = auth/login
epic = auth
ready = false

[branch "auth/2fa"]
depends = auth/register
epic = auth
ready = false
```

### 环境变量

```bash
# 调试选项
export GIT_PR_DEBUG=1        # 启用调试模式
export GIT_PR_VERBOSE=1      # 详细输出
export GIT_PR_TRACE=1        # 跟踪执行

# 行为控制
export GIT_PR_NO_COLOR=1     # 禁用颜色
export GIT_PR_EDITOR=vim     # 指定编辑器
export GIT_PR_PAGER=less     # 指定分页器

# 路径覆盖
export GIT_PR_EPIC_DIR=@my-epics    # Epic目录
export GIT_PR_TEMP_DIR=@my-temp     # 临时目录
export GIT_PR_CONFIG_DIR=~/.git-pr  # 配置目录
```

## JSON API

### 状态查询API

#### 分支状态
```bash
git-pr status --json
```

**输出格式**:
```json
{
  "epics": [
    {
      "name": "auth",
      "description": "用户认证系统",
      "worktree_path": ".worktrees/auth--login",
      "branches": [
        {
          "name": "auth/login",
          "status": "ready",
          "commits_ahead": 0,
          "commits_behind": 0,
          "dependencies": ["main"],
          "dependents": ["auth/register", "auth/2fa"],
          "pr_number": null,
          "last_sync": "2024-01-01T10:00:00Z",
          "conflicts": []
        }
      ]
    }
  ],
  "temp_branches": [
    {
      "name": "hotfix/bug-123",
      "worktree_path": ".worktrees/hotfix--bug-123",
      "status": "draft",
      "pr_number": 67
    }
  ],
  "disk_usage": {
    "total": "1.2GB",
    "epics": "900MB",
    "temp": "300MB"
  }
}
```

#### 依赖关系
```bash
git-pr deps tree --json
```

**输出格式**:
```json
{
  "dependencies": {
    "auth/login": ["main"],
    "auth/register": ["auth/login"],
    "auth/2fa": ["auth/register"],
    "auth/social": ["auth/login"]
  },
  "tree": {
    "main": {
      "children": ["auth/login"],
      "level": 0
    },
    "auth/login": {
      "children": ["auth/register", "auth/social"],
      "level": 1
    },
    "auth/register": {
      "children": ["auth/2fa"],
      "level": 2
    }
  },
  "cycles": [],
  "orphans": []
}
```

### 操作API

#### 同步预览
```bash
git-pr sync --preview --json
```

**输出格式**:
```json
{
  "plan": {
    "source_branch": "auth/login",
    "target_branches": ["auth/register", "auth/2fa"],
    "operations": [
      {
        "type": "merge",
        "from": "auth/login",
        "to": "auth/register",
        "commits": 3,
        "files_changed": ["src/auth/login.js", "src/auth/utils.js"]
      },
      {
        "type": "merge", 
        "from": "auth/login",
        "to": "auth/2fa",
        "commits": 3,
        "files_changed": ["src/auth/login.js", "src/auth/utils.js"]
      }
    ],
    "potential_conflicts": [
      {
        "file": "src/auth/utils.js",
        "branches": ["auth/register", "auth/2fa"],
        "type": "content",
        "severity": "medium"
      }
    ],
    "estimated_time": "2-3 minutes"
  }
}
```

## 插件API

### 插件结构
```
~/.git-pr/plugins/my-plugin/
├── manifest.json
├── commands/
│   └── my-command.sh
├── hooks/
│   ├── pre-sync.sh
│   └── post-sync.sh
└── lib/
    └── helper.sh
```

### 插件清单
```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "My custom plugin",
  "author": "Author Name",
  "git_pr_version": ">=1.0.0",
  "commands": [
    {
      "name": "my-command",
      "description": "My custom command",
      "script": "commands/my-command.sh"
    }
  ],
  "hooks": [
    {
      "name": "pre-sync",
      "script": "hooks/pre-sync.sh"
    }
  ],
  "config": {
    "my_setting": {
      "type": "string",
      "default": "default_value",
      "description": "My setting description"
    }
  }
}
```

### Hook接口

#### pre-sync Hook
```bash
#!/bin/bash
# hooks/pre-sync.sh

# 参数
SOURCE_BRANCH="$1"
TARGET_BRANCHES="$2"  # 空格分隔的分支列表
SYNC_STRATEGY="$3"

# 返回值
# 0: 继续执行
# 1: 终止同步
# 2: 跳过当前操作

# 示例：检查分支是否ready
for branch in $TARGET_BRANCHES; do
  if ! is_branch_ready "$branch"; then
    echo "分支未ready: $branch"
    exit 1
  fi
done
```

#### conflict-resolve Hook
```bash
#!/bin/bash
# hooks/conflict-resolve.sh

CONFLICT_FILE="$1"
CONFLICT_TYPE="$2"  # file|content|rename|delete

# 自定义冲突解决逻辑
case "$CONFLICT_TYPE" in
  "content")
    # 尝试自动解决内容冲突
    if auto_resolve_content_conflict "$CONFLICT_FILE"; then
      git add "$CONFLICT_FILE"
      exit 0  # 冲突已解决
    fi
    ;;
esac

exit 1  # 无法解决，交给默认处理器
```

### 命令扩展接口

```bash
#!/bin/bash
# commands/my-command.sh

# 命令帮助
show_help() {
  cat <<EOF
git-pr my-command - 我的自定义命令

用法: git-pr my-command [选项] <参数>

选项:
  -h, --help     显示帮助
  -v, --verbose  详细输出

示例:
  git-pr my-command --verbose arg1
EOF
}

# 命令执行
execute_command() {
  local verbose=false
  local args=()
  
  # 参数解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -v|--verbose)
        verbose=true
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  
  # 命令逻辑
  if [[ "$verbose" == "true" ]]; then
    echo "执行详细模式..."
  fi
  
  echo "处理参数: ${args[*]}"
}

# 入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  execute_command "$@"
fi
```

## 错误代码

### 命令错误码
- `0` - 成功
- `1` - 一般错误
- `2` - 参数错误
- `3` - 环境错误
- `4` - Git错误
- `5` - 冲突错误
- `6` - 权限错误
- `7` - 磁盘空间错误

### 详细错误分类
```bash
# 用户错误 (10-19)
ERR_INVALID_ARGS=10
ERR_MISSING_ARGS=11
ERR_UNKNOWN_COMMAND=12

# 环境错误 (20-29)  
ERR_NOT_GIT_REPO=20
ERR_DIRTY_WORKTREE=21
ERR_NO_UPSTREAM=22

# 业务错误 (30-39)
ERR_BRANCH_EXISTS=30
ERR_CIRCULAR_DEPS=31
ERR_MERGE_CONFLICT=32

# 系统错误 (40-49)
ERR_DISK_FULL=40
ERR_PERMISSION_DENIED=41
ERR_COMMAND_NOT_FOUND=42
```

这个API设计提供了完整的命令行接口、灵活的配置系统、结构化的数据输出和可扩展的插件机制。