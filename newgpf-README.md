# GPF (Git PR Flow) - 新版本

> 为了方便理解，本文档的示例 epic 我们用 auth，Epic 的子 Feature我们用 auth-login，git 分支我们会创建为 epic-auth-e 和 epic-auth-login-ef，worktree 目录名与 git 分支名完全一致：epic-auth-e 和 epic-auth-login-ef(gpf工具会自动补全前缀`epic-`和自动补全后缀`-e`或`-ef`；auth 与 auth-login，使用`-`，没有使用`/`，如 auth/login 命名是为了避免git的冲突，git 的分支引用机制不允许同时存在 refs/heads/xx 和 refs/heads/xx/yy，会产生冲突)

结合 git worktree 和 Epic 的 **PR 友好工具**，专为 GitHub PR 工作流和并行开发设计的 cli 工具。

**核心理念**：GPF 不替代 GitHub PR，而是让 PR 工作流更高效
- **所有分支都推送到 GitHub**：Epic 和 Feature 分支都要 push
- **下到上只能 PR**：push -> Epic-Feature -> pr -> Epic -> review -> 可清理 Epic-Feature 本地worktree目录和本地、远程分支、push -> Epic -> pr -> Develop -> review -> 可清理 Epic 本地worktree目录和本地、远程分支，通过 GitHub PR 完成
- **上到下本地 sync**：pull -> Develop -> Epic -> merge -> Epic-Feature -> merge， 通过 GPF sync 命令完成

> 📖 **文档导航**: [安装指南](docs/newgpf-INSTALL.md) | [架构设计](docs/newgpf-ARCHITECTURE.md) | [命令详细](docs/newgpf-COMMANDS.md) | [核心组件](docs/newgpf-CORE-COMPONENTS.md) | [GitHub集成](docs/newgpf-GITHUB-CLI-INTEGRATION.md) | [术语表](docs/newgpf-术语表.md)

> 详见 [术语表](docs/newgpf-术语表.md) 了解标准术语定义。

## gpf 核心理念

- 本 cli 工具将常用的 git 命令进行封装，提供更友好的工作流体验
- **简洁高效**：只有5个核心命令 `start` `pr` `clean` `status` `sync`
- **操作友好**：无参数进入交互模式，有参数直接执行，错误信息包含解决方案
- **AI友好**：worktree 模式，AI可以同时开发多个功能而目录不冲突，命令设计也对ai友好，ai容易理解本工具并代人自动操作
- **🆕 智能切换**：不管在哪个目录执行命令，都检测是否可以切换到正确的目标环境
- **规范的工作流**：将良好的工作流封装为五个命令，使用命令就符合工作流
- **工作流保护**：自动检查状态，防止数据丢失
- **零心智负担**：智能推断环境，减少决策
- **🔄 自动同步**：智能检测同步需求，确保基于最新代码开发
- **📊 状态透明**：完整的状态可视化，随时了解开发进度

## gpf 背景知识
### Epic 理念
#### Epic 是什么
Epic 的概念是 Epic 通常代表一个较大的功能模块，基于main 或 develop 分出一个主要 epic 分支（如要开发一个 auth）， 再基于 epic 创建 Epic 的子 Feature 分支(如login，register等)，开发是在 Epic 的子 Feature 分支进行（就像不在main 或develop 开发，而是在 feature 分支开发一样）。

**GPF 的 PR 工作流**：
1. Epic 的子 Feature 开发完成 → **push 到 GitHub** → **在 GitHub 创建 PR** 到 epic 分支
2. Epic 达到里程碑 → **push 到 GitHub** → **在 GitHub 创建 PR** 到 develop 分支  
3. 审核通过后，**在 GitHub 合并 PR**
4. 本地执行 `gpf sync` **pull 最新代码**，保持同步

如基于 develop 创建 auth epic，再基于 auth 创建 auth-login Feature。auth-login 开发完成后，push 到 GitHub 并创建 PR 到 auth 分支。auth 达到里程碑后，push 到 GitHub 并创建 PR 到 develop 分支。这里 auth 就是 epic 大功能分支，auth-login 就是 Epic 的子 Feature 分支。

```bash
# git 分支示例
develop             # 主开发分支
└── epic-auth-e     # Epic 分支(为了体现使用的是Epic加`-e`后缀标识，这里示例是 epic-auth-e)
    └── epic-auth-login-ef  # Epic 的子 Feature分支（这里示例是 epic-auth-login-ef）
```

#### Epic + GPF 的好处
1. **并行开发**：多个功能模块可以并行开发，互不干扰
2. **分支清晰**：功能模块的分支结构清晰，易于管理
3. **快速切换**：可以快速切换到不同的功能模块进行开发
4. **版本控制**：可以方便地管理和控制不同功能模块的版本
5. **🆕 PR 工作流支持**：简化 GitHub PR 的创建和管理
6. **🆕 自动同步**：确保本地代码始终基于最新的上游代码

#### Epic 的实践建议
- Epic 拆解合理，不要覆盖面太大也不要太小，优先实现应用的 MVP 核心功能，明确 AC 验收标准
- Epic 的子 Feature 拆解应优先实现 Epic 的子 Feature 的 MVP 核心功能，再逐步优化，明确 AC 验收标准，避免 PR 因需求模糊被反复修改
- 将一个应用拆分出合适的多个 Epic，每个 Epic 拆分为合适的 Epic 的子 Feature（如 Epic: auth；Epic 的子 Feature: auth-login、auth-register），确定 Epic 和 Epic 的子 Feature 的验收标准。
技术团队评估可行性，制定 roadmap 文档
- pr 关联 epic issue 和 epic 的 Epic 的子 Feature issue（或关联第三方任务管理工具的任务）
- 保持 PR 小型化：单个 PR 尽量只解决一个问题，避免大规模改动，便于审查

### worktree 是什么
#### Worktree 隔离开发环境
worktree 是 git 的一个功能，它可以不使用 git checkout 切换分支，**直接切换到指定目录就进入这个分支环境**

比如创建了两个 worktree，我们在两个目录下可以同时看到两个分支下的文件内容，比如A git分支下面创建了a.md，b git分支下创建了b.md。传统方法进入A 电脑的目录下你看不到b.md。有了worktree，你可以同时在这两个目录看到a.md和b.md

现在有 worktree，特别是可以让多个AI或同一个AI的多个窗口，进入不同目录就可以同时开发了。

#### ✅ Worktree最佳实践：cd 替代 git checkout
```bash
# ❌ 传统方式：需要频繁切换分支环境
# 切换到Epic环境
# 修改文件...
# 切换到Feature环境 
# 修改文件...
# 切换到主开发环境

# ✅ Worktree方式：目录即环境
# 切换到Epic环境          
# 修改文件...
# 切换到Feature环境   
# 修改文件...
# 切换到根目录环境
```

创建worktree的命令为`git worktree add -b epic-auth-login ../epic-auth-login epic-auth`，这个命令的意思是，基于 epic-auth 分支创建 epic-auth-login 分支，worktree 的目录名为 epic-auth-login

创建后目录在项目根目录的 .worktrees/ 下

直接切换到这个目录，就自动进入这个分支环境，不需要 git chekckout 命令

删除命令为：
```bash
git worktree remove ../<directory-name> # 删除 Worktree 目录
git branch -d <branch-name>     # 删除对应的本地分支
```


### epic 结合 worktree
结合是什么样？有什么好处
✅ 显著提升多任务并行效率
✅ 并行开发：worktree 物理隔离，互不干扰
✅ 分支清晰：功能分支归属明确，PR 目标指向 Epic(合并路径：Epic 的子 Feature分支 -> epic分支，epic分支 -> develop分支)
✅ 快速切换：无需反复 git stash 或切换分支状态，切换到目标环境即可

#### epic 分支与 worktree 关联创建
使用 epic 为 auth 与 Epic 的子 Feature为 auth-login 示例
```bash
# 分两步，创建 git 分支，创建 worktree
# 1.创建 Epic 分支，这里示例是：epic-auth-e
git checkout -b epic-auth-e develop  # 基于 develop 创建 epic-auth-e 分支，并切换到该分支
# 2.创建 worktree，这里示例是：epic-auth-e
git worktree add ../epic-auth-e epic-auth-e  # 基于 epic-auth-e 分支创建目录名为 epic-auth-e 的 Worktree
```
```bash
# 合并为一个命令
git worktree add -b epic-auth-e ../epic-auth-e develop
```

#### Epic 的子 Feature分支与 worktree 关联创建
使用 epic 为 auth 与 Epic 的子 Feature为 auth-login 示例
```bash
# 分两步，创建 git 分支，创建 worktree
# 1.创建 Epic 的子 Feature分支，这里示例是：epic-auth-login-ef
git checkout -b epic-auth-login-ef epic-auth-e  # 基于 epic-auth-e 分支创建 epic-auth-login-ef 分支，并切换到该分支
# 2.创建 worktree，这里示例是：epic-auth-login-ef
git worktree add ../epic-auth-login-ef epic-auth-login-ef
```
```bash
# 合并为一个命令
git worktree add -b epic-auth-login-ef ../epic-auth-login-ef epic-auth-e
```

## gpf 快速开始

**命名规则：**
- Epic名称：可包含小写字母、数字、连字符(-)、下划线(_)
- `epic-`前缀可省略，系统自动补全
- 受Git worktree限制，不支持斜杠(/)等文件系统特殊字符

**明确命令格式：**
```bash
# 1. 创建Epic开发环境
gpf start -e auth develop
# 用户输入: auth, 系统创建: epic-auth-e分支和worktree

# 2. 创建Epic 的子 Feature（支持三种输入格式）
gpf start -ef login auth                # 最简格式
gpf start -ef auth-login auth          # 包含Epic前缀
gpf start -ef epic-auth-login-ef auth  # 完整格式
# 以上三种输入都创建: epic-auth-login-ef分支和worktree

# 3. 开发完成后创建PR
gpf pr

# 4. 清理已合并的分支  
gpf clean              # 预览模式（默认）
gpf clean --safe       # 安全清理
gpf clean --force      # 强制清理（危险）
```

## 核心命令

GPF 提供5个核心命令，覆盖完整的开发工作流：

### `gpf start` - 开始开发

**命令格式：**
```bash
# 无参数：交互模式
gpf start

# 创建Epic：-e 参数
gpf start -e <epic-name> <base-branch>

# 创建Epic 的子 Feature：-ef 参数
gpf start -ef <feature-name> <epic-name>
```

**参数说明：**
- `-e`: 创建Epic分支
- `-ef`: 创建Epic 的子 Feature分支
- `<epic-name>`: Epic名称（可省略epic-前缀）
- `<feature-name>`: 功能名称（可省略Epic前缀，系统自动补全）
- `<base-branch>`: 基础分支（通常是develop）

**🎯 智能前缀后缀处理：**

系统精确处理用户输入的前缀和后缀，防止重复和错误：

| 命令场景 | 用户输入示例 | 系统处理过程 | 最终结果 |
|---------|-------------|-------------|----------|
| Epic创建 | `gpf start -e auth develop` | 添加前缀+后缀 | epic-auth-e |
| Epic创建 | `gpf start -e epic-auth develop` | 去重复前缀+添加后缀 | epic-auth-e |
| Epic创建 | `gpf start -e auth-e develop` | 添加前缀+验证后缀 | epic-auth-e |
| Epic创建 | `gpf start -e epic-auth-e develop` | 验证完整格式 | epic-auth-e |
| Feature创建 | `gpf start -ef login auth` | 智能补全Epic前缀 | epic-auth-login-ef |
| Feature创建 | `gpf start -ef auth-login auth` | 处理包含Epic的Feature | epic-auth-login-ef |
| **错误检测** | `gpf start -ef auth-login-e auth` | **后缀不匹配错误** | ❌ 报错 |

**🛡️ 关键错误防护：**
- **防止重复前缀**：`epic-epic-auth-e` → `epic-auth-e`
- **防止重复后缀**：`auth-e-e` → `auth-e`  
- **后缀匹配验证**：`-ef` 命令不能接受 `-e` 后缀
- **环境验证**：Feature环境中不能使用 `-e` 后缀

**核心设计原则：**
1. **start命令**: 根据`-e`/`-ef`参数类型验证和补全用户输入
2. **其他命令**: 根据当前环境(Epic/Feature分支)自动补全
3. **智能容错**: 用户可省略后缀(自动补全)或手动添加(验证匹配)
4. **错误提示**: 后缀不匹配时给出明确的错误信息和建议

**命令示例：**
```bash
# 创建Epic
gpf start -e auth develop
→ Git分支: epic-auth-e
→ Worktree: .worktrees/epic-auth-e

# 创建子功能（简化输入）
gpf start -ef login auth
→ 📍 切换到Epic环境 (.worktrees/epic-auth-e)
→ 自动补全: auth-login
→ Git分支: epic-auth-login-ef
→ Worktree: .worktrees/epic-auth-login-ef

# 创建子功能（完整输入）
gpf start -ef auth-login auth
→ 📍 切换到Epic环境 (.worktrees/epic-auth-e)
→ Git分支: epic-auth-login-ef
→ Worktree: .worktrees/epic-auth-login-ef
```

**交互式模式：**

创建 Epic
```bash
gpf start
# 欢迎使用 gpf 工具
# 由于没有带参数您已经进入交互模式
# 请选择要创建 Epic 还是创建 Epic 的子 Feature
# 1. Epic，2. Epic 的子 Feature，3. 退出
# 请输入你的选择：1
# 下方名称开头的`epic-`前缀，手工输入时可省略，会自动补全；输入 `q:` 退出
# 请输入 Epic 名称：auth
# 请输入 git Base 分支：develop
# 创建成功！
# 工作目录：.worktrees/epic-auth-e
# 分支名称：epic-auth-e
# 分支状态：未推送
# 分支状态：未合并
```

创建 Epic 的子 Feature
```bash
gpf start
# 欢迎使用 gpf 工具
# 由于没有带参数您已经进入交互模式
# 请选择要创建 Epic 还是创建 Epic 的子 Feature
# 1. Epic，2. Epic 的子 Feature，3. 退出，或输入 `q:` 退出
# 请输入你的选择：2
# 上一步您选择了创建 Epic 的子 Feature，接下来请选择或输入 Epic 的名称；或输入 `q:` 退出
# 请选择或输入 Epic 的名称：auth
# 您已经选择或输入了 Epic 的名称：auth
# 接下来请选择或输入 Epic 的子 Feature名称；或输入 `q:` 退出
# 请输入 Epic 子功能的名称：login
# 创建成功！
# 工作目录：.worktrees/epic-auth-login-ef
# 分支名称：epic-auth-login-ef
# 分支状态：未推送
# 分支状态：未合并
```

### `gpf pr` - 创建Pull Request

**命令格式：**
```bash
# 自动模式（根据当前环境调用gh pr create）
gpf pr

# 指定目标模式（切换到目标环境后调用gh pr create）
gpf pr <target>

# 指定关联issue
gpf pr --issue 123,456

# 帮助信息
gpf pr --help
gpf pr -h
```

**环境要求：**
- **必须在正确环境内执行**：Epic环境（`*-e`）或Feature环境（`*-ef`）
- 不支持在项目根目录执行，会引导用户切换到正确目录
- 依赖GitHub CLI工具，自动检查安装和配置状态

**智能处理逻辑：**
- **无参数**: 根据当前环境调用`gpf status`确定PR状态
  - Epic环境：创建 `epic → develop` 的PR
  - Feature环境：创建 `feature → epic` 的PR
- **有参数**: 智能切换到目标环境后创建PR
  - `gpf pr auth` → 切换到 `.worktrees/epic-auth-e`
  - `gpf pr login` → 切换到当前Epic的Feature环境

**强制要求和检查：**
- **Issue关联**: PR必须关联GitHub issue（最佳实践）
  - 命令参数: `--issue 123,456`
  - 分支名解析: `epic-auth-123-e` 自动识别
  - 交互式输入（AI友好的非交互式环境支持）
- **状态验证**: 调用`gpf status`进行完整的状态检查
  - 本地Git状态：工作区、暂存区、推送状态
  - GitHub PR状态：是否已有PR、PR审核状态
  - 分支同步状态：是否基于最新上游代码

**执行流程：**
1. 检查GitHub CLI工具状态
2. 验证当前在正确的worktree环境中
3. 执行智能切换（如有目标参数）
4. 调用`gpf status`检查PR就绪状态
5. 强制要求关联issue
6. 调用 `gh pr create` 创建GitHub PR
7. 自动执行 `gh pr view` 显示创建结果

### `gpf clean` - 清理分支

```bash
# 预览模式（只分析，不清理）
gpf clean                    # 基于当前环境预览
gpf clean <target>           # 预览指定目标

# 安全清理（只清理已保存+已提交+已合并的分支）
gpf clean --safe             # 基于当前环境安全清理  
gpf clean --safe <target>    # 安全清理指定目标

# 强制清理（清理所有分支，危险操作，将丢失数据）
gpf clean --force            # 基于当前环境强制清理
gpf clean --force <target>   # 强制清理指定目标
```

### `gpf status` - 查看状态

```bash
# 环境感知的状态显示
gpf status                   # 根据当前环境智能显示状态
gpf status <epic>            # 显示指定Epic及其所有子features状态
gpf status <epic> <feature>  # 显示指定feature的详细状态

# GitHub PR状态显示
gpf status --pr              # 仅显示GitHub PR状态信息

# 状态信息包括
# - 未保存修改数量
# - 未提交内容数量  
# - 未推送提交数量
# - 分支合并状态
# - 🆕 GitHub PR状态：PR是否存在、审核状态、合并状态
# - 🆕 操作权限提示：当前环境可执行的gpf命令
# - 开发进度估算
```

**GitHub CLI集成功能：**
- **PR状态检查**：自动检查分支是否已有PR，显示PR号码、标题和链接
- **审核状态显示**：显示PR的review状态（待审核/已审核/需修改/已合并）
- **操作权限提示**：根据PR状态提示可执行的操作（gpf pr/clean等）
- **环境要求检查**：如果GitHub CLI未配置，提供详细的配置指导

**状态显示示例：**
```bash
$ gpf status
📁 当前环境: Feature分支 (.worktrees/epic-auth-login-ef)
🎯 Git状态:
   ✅ 工作区: 干净
   ✅ 暂存区: 干净
   ✅ 推送状态: 已推送到远程
   
🔗 GitHub PR状态:
   📋 PR #123: 实现用户登录功能
   🔗 链接: https://github.com/user/repo/pull/123
   👥 审核状态: ⏳ 等待审核
   🎯 下一步: 等待代码审核
   
🎯 操作权限:
   ❌ gpf pr: 已有PR存在
   ❌ gpf clean: 等待审核完成
```

### `gpf sync` - 同步分支

```bash
# 环境感知的智能同步
gpf sync                     # 根据当前环境智能同步
gpf sync <epic>              # 同步指定Epic及其所有子features

# 同步方向（上往下）
# develop → epic → epic-features
# 
# 同步流程
# 1. Pull 最新远程代码
# 2. 检查同步安全性
# 3. 执行级联同步
# 4. 推送同步结果
```

## 命名约束

**技术限制说明：**
GPF使用Git worktree，分支名即目录名，因此受文件系统命名限制：

**支持的字符：**
- ✅ 小写字母(a-z)、数字(0-9)
- ✅ 连字符(-)、下划线(_)
- ✅ 点号(.) - 但不建议开头使用

**不支持的字符：**
- ❌ 斜杠(/) - 文件系统路径分隔符
- ❌ 反斜杠(\) - Windows路径分隔符
- ❌ 冒号(:) - Windows驱动器分隔符
- ❌ 其他特殊符号 - 可能导致目录创建失败

**错误处理示例：**
```bash
$ gpf start -e user/auth develop
❌ 错误：名称包含不支持的字符 "/"
原因：Git worktree使用分支名作为目录名
建议：使用 user_auth 或 user-auth

$ gpf start -ef login@check auth
❌ 错误：名称包含不支持的字符 "@"
原因：文件系统不支持该字符作为目录名
建议：使用 login_check 或 login-check
```

## 设计原则

### 1. 目录结构清晰
```
.worktrees/
├── epic-auth-e/         # Epic工作目录
├── epic-auth-login-ef/  # Epic 的子 Feature 工作目录
└── epic-auth-logout-ef/ # Epic 的子 Feature 工作目录
```

### 2. 分支命名规范
```
epic-auth-e         # Epic分支
epic-auth-login-ef  # Epic 的子 Feature 分支
epic-auth-logout-ef # Epic 的子 Feature 分支
```

### 3. AI友好交互
- 无参数 = 交互模式（人类友好）
- 有参数 = 直接执行（AI友好）
- 错误信息包含具体解决方案

### 4. 工作流保护
- 敏感操作前自动状态检查
- 未保存内容阻止危险操作
- 提供强制选项和明确警告

## 与旧版本的改进

1. **命令简化**：从8个命令精简到5个核心命令，覆盖完整工作流
2. **职责清晰**：每个命令职责单一，不互相影响
3. **公共组件抽象**：路径、上下文、状态检查、同步等完全解耦
4. **错误处理统一**：一致的错误格式和解决方案引导
5. **测试友好**：每个组件可独立测试，修改影响范围可控
6. **🆕 自动同步**：集成到start和pr命令中，确保代码同步性
7. **🆕 状态透明**：完整的状态可视化和进度跟踪

## 🚀 快速安装

NewGPF需要GitHub CLI以实现完整的PR功能：

```bash
# 一键安装（推荐）
curl -fsSL https://raw.githubusercontent.com/your-repo/git-pr-cli/main/scripts/install.sh | bash

# 验证安装
gpf --version
gh auth status
```

详见 [安装指南](docs/newgpf-INSTALL.md) | [GitHub CLI集成](docs/newgpf-GITHUB-CLI-INTEGRATION.md)

> 更多技术细节参考 [核心组件设计](docs/newgpf-CORE-COMPONENTS.md)。

## 开发指南

详见 [DEVELOPMENT.md](docs/DEVELOPMENT.md)

> 了解重构进展和计划参考 [重构路线图](docs/newgpf-roadmap.md)。