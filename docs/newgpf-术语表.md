# NewGPF 标准术语表

> 本文档定义了 NewGPF 项目中使用的标准术语，确保所有文档和代码的一致性。

## 📚 核心概念术语

### Epic 相关
| 术语 | 标准表述 | 说明 | 示例 |
|------|----------|------|------|
| **Epic** | Epic | 大功能模块，基于主分支创建 | auth、payment、user-system |
| **Epic 的子 Feature** | Epic 的子 Feature | Epic 下的具体功能实现 | login、register、2fa |
| **Epic 分支** | Epic 分支 | Epic 对应的 Git 分支 | epic-auth-e |
| **Feature 分支** | Feature 分支 | Epic 的子 Feature 对应的 Git 分支 | epic-auth-login-ef |

### 分支命名术语
| 术语 | 标准表述 | 格式 | 示例 |
|------|----------|------|------|
| **前缀标识** | epic- 前缀 | epic- | epic-auth-e |
| **后缀标识** | -e 后缀 / -ef 后缀 | -e / -ef | auth-e / login-ef |
| **Epic 后缀** | -e 后缀 | -e | epic-auth-e |
| **Feature 后缀** | -ef 后缀 | -ef | epic-auth-login-ef |

### Epic Roadmap 术语
| 术语 | 标准表述 | 说明 | 示例 |
|------|----------|------|------|
| **Epic Roadmap** | Epic Roadmap | Epic 的开发规划文档 | epic-auth-roadmap.md |
| **规划驱动开发** | 规划驱动开发 | 先完善 roadmap 再开发的工作模式 | Epic创建→完善roadmap→创建Feature |
| **Epic分支保护** | Epic分支保护 | 限制Epic分支只能修改roadmap的保护机制 | 阻止在Epic分支修改业务代码 |
| **Roadmap模板** | Roadmap模板 | 自动生成的包含占位符的初始roadmap | 包含 [占位符] 的模板文件 |
| **占位符** | 占位符 | roadmap模板中需要用户填充的部分 | [当前Epic要解决的核心问题] |

### 工作环境术语
| 术语 | 标准表述 | 说明 | 路径示例 |
|------|----------|------|----------|
| **Worktree** | Worktree | Git 工作树，物理隔离的开发环境 | .worktrees/epic-auth-e |
| **Epic 环境** | Epic 环境 | Epic 分支对应的 Worktree 环境 | .worktrees/epic-auth-e |
| **Feature 环境** | Feature 环境 | Feature 分支对应的 Worktree 环境 | .worktrees/epic-auth-login-ef |
| **根目录环境** | 根目录环境 | 项目根目录环境 | /project/root |

## 🎯 命令相关术语

### 命令模式
| 术语 | 标准表述 | 说明 | 示例 |
|------|----------|------|------|
| **交互式模式** | 交互式模式 | 无参数进入的用户引导模式 | `gpf start` |
| **参数化模式** | 参数化模式 | 带参数直接执行的模式 | `gpf start -e auth develop` |
| **自动模式** | 自动模式 | 基于环境自动判断的模式 | `gpf pr` |

### 命令参数
| 术语 | 标准表述 | 说明 | 用法 |
|------|----------|------|------|
| **-e 参数** | -e 参数 | 创建 Epic 的标识参数 | `gpf start -e auth develop` |
| **-ef 参数** | -ef 参数 | 创建 Epic 的子 Feature 的标识参数 | `gpf start -ef login auth` |

## 🔄 操作流程术语

### 输入处理
| 术语 | 标准表述 | 说明 | 示例 |
|------|----------|------|------|
| **智能补全** | 智能补全 | 系统自动补全用户输入的前缀后缀 | auth → epic-auth-e |
| **前缀处理** | 前缀处理 | 处理用户输入的 epic- 前缀 | epic-auth → auth |
| **后缀处理** | 后缀处理 | 处理用户输入的 -e/-ef 后缀 | auth-e → auth |
| **输入验证** | 输入验证 | 验证用户输入格式的正确性 | 后缀匹配检查 |

### 环境切换
| 术语 | 标准表述 | 说明 | 示例 |
|------|----------|------|------|
| **智能切换** | 智能切换 | 智能检测现有worktree，存在则自动切换，不存在则创建 | 自动进入对应 Worktree |
| **环境检测** | 环境检测 | 检测当前执行环境类型 | epic/feature/root |
| **切换到Epic环境** | 切换到Epic环境 | 进入Epic的worktree目录+自动切换到Epic分支 | 从根目录切换到 .worktrees/epic-auth-e |
| **切换到Feature环境** | 切换到Feature环境 | 进入Feature的worktree目录+自动切换到Feature分支 | 从Epic环境切换到 .worktrees/epic-auth-login-ef |
| **切换到根目录环境** | 切换到根目录环境 | 进入项目根目录+切换到指定分支 | 从worktree切换到根目录的develop分支 |

## 🛡️ 安全和验证术语

### 状态检查
| 术语 | 标准表述 | 说明 | 检查项 |
|------|----------|------|--------|
| **工作区干净** | 工作区干净 | 没有未保存的修改 | git diff-files |
| **暂存区为空** | 暂存区为空 | 没有未提交的内容 | git diff-index --cached |
| **分支已推送** | 分支已推送 | 分支已推送到远程 | origin/branch 存在 |
| **分支已合并** | 分支已合并 | 分支已合并到目标分支 | 无未合并提交 |

### 安全级别
| 术语 | 标准表述 | 标识 | 说明 |
|------|----------|------|------|
| **安全级别** | 安全级别 | 🟢🟡🔴 | 分支清理的安全程度 |
| **安全清理** | 安全清理 | 🟢 | 已保存+已提交+已合并 |
| **警告清理** | 警告清理 | 🟡 | 已合并但有未推送提交 |
| **危险清理** | 危险清理 | 🔴 | 未合并或有未提交修改 |

## 📋 标准示例

### 基础示例
| 场景 | Epic 名称 | Feature 名称 | 完整分支名 |
|------|-----------|--------------|------------|
| **用户认证** | auth | login | epic-auth-login-ef |
| **用户认证** | auth | register | epic-auth-register-ef |
| **用户认证** | auth | logout | epic-auth-logout-ef |
| **支付系统** | payment | stripe | epic-payment-stripe-ef |
| **支付系统** | payment | paypal | epic-payment-paypal-ef |

### 复杂示例（特殊场景）
| 场景 | Epic 名称 | Feature 名称 | 说明 |
|------|-----------|--------------|------|
| **用户系统重构** | user-system | profile-redesign | 大型重构项目 |
| **API 版本升级** | api-v2 | endpoint-migration | 版本升级项目 |
| **性能优化** | performance-opt | database-index | 性能专项 |

## 🔧 技术实现术语

### 架构组件
| 术语 | 标准表述 | 说明 | 位置 |
|------|----------|------|------|
| **Core 组件** | Core 组件 | 核心公共组件 | lib/core/ |
| **Command 组件** | Command 组件 | 命令实现组件 | lib/commands/ |
| **基础方法** | 基础方法 | 原子级别的功能方法 | core/*.sh |
| **组合方法** | 组合方法 | 多个基础方法的组合 | core/*.sh |
| **多命令共用方法** | 多命令共用方法 | 被多个命令使用的方法 | core/*.sh |

### 目录结构术语
| 术语 | 标准表述 | 说明 | 路径示例 |
|------|----------|------|----------|
| **Epic Roadmap目录** | docs/epic_roadmap/ | 存放所有Epic roadmap的目录 | docs/epic_roadmap/ |
| **Roadmap文件** | epic-*-roadmap.md | Epic对应的roadmap文件 | docs/epic_roadmap/epic-auth-roadmap.md |
| **Worktree目录** | .worktrees/ | 存放所有worktree的根目录 | .worktrees/ |
| **模板验证** | 模板验证 | 检查roadmap是否还包含未填充占位符 | 检测 [占位符] 数量 |

### 新版本文件命名
等新版本实现完毕再清理老版本文件，之后再把新版本的前缀去掉
| 类型 | 命名规则 | 示例 | 说明 |
|------|----------|------|------|
| **文档文件** | newgpf-*.md | newgpf-README.md | 新版本文档 |
| **组件文件** | newgpf-*.sh | newgpf-context.sh | 功能组件 |
| **命令文件** | newgpf-*.sh | newgpf-start.sh | 命令实现 |

## 📖 新版本文档引用规范

### 文档间引用
- **主文档**: [newgpf-README.md](newgpf-README.md)
- **架构设计**: [newgpf-ARCHITECTURE.md](newgpf-ARCHITECTURE.md)  
- **命令详细**: [newgpf-COMMANDS.md](newgpf-COMMANDS.md)
- **核心组件**: [newgpf-CORE-COMPONENTS.md](newgpf-CORE-COMPONENTS.md)
- **重构路线**: [newgpf-roadmap.md](newgpf-roadmap.md)
- **术语表**: [newgpf-术语表.md](newgpf-术语表.md)

### 引用格式
```markdown
详见 [术语表](newgpf-术语表.md#epic-相关) 中的 Epic 相关定义。
参考 [架构设计](newgpf-ARCHITECTURE.md#核心设计原则) 了解设计原则。
```

## ⚠️ 废弃术语

### 基础术语废弃
| 废弃术语 | 标准替换 | 原因 |
|----------|----------|------|
| Epic 的子功能 | Epic 的子 Feature | 术语统一 |
| 功能分支 | Feature 分支 | 术语明确 |
| 子功能分支 | Feature 分支 | 术语简化 |
| user-auth（非特殊场景） | auth | 示例简化 |

### 环境概念废弃
| 废弃术语 | 标准替换 | 原因 |
|----------|----------|------|
| 上下文 | 环境 | 概念统一 |
| 上下文检测 | 检测当前环境 | 动作表述标准化 |
| 当前上下文 | 当前环境 | 概念统一 |
| 上下文类型 | 环境类型 | 概念统一 |
| 上下文驱动 | 环境驱动 | 概念统一 |

### 切换动作废弃
| 废弃术语 | 标准替换 | 原因 |
|----------|----------|------|
| 自动切换 | 智能切换 | 术语统一 |
| 智能目录切换功能 | 智能切换 | 术语简化 |
| 切换目录 | 切换到XX环境 | 抽象为环境概念 |
| 切换worktree | 切换到XX环境 | 抽象为环境概念 |
| 切换分支 | 切换到XX环境 | 抽象为环境概念 |
| 切换git分支 | 切换到XX环境 | 抽象为环境概念 |
| 进入目录 | 切换到XX环境 | 统一动作表述 |
| 进入worktree | 切换到XX环境 | 统一动作表述 |
| 进入epic | 切换到Epic环境 | 统一动作表述 |
| 进入feature | 切换到Feature环境 | 统一动作表述 |
| 切换Epic | 切换到Epic环境 | 明确目标环境 |
| 切换Feature | 切换到Feature环境 | 明确目标环境 |
| Epic切换 | Epic环境切换 | 名词形式统一 |
| Feature切换 | Feature环境切换 | 名词形式统一 |

## 🎯 术语使用原则

1. **一致性原则**: 同一概念在所有文档中使用相同术语
2. **简洁性原则**: 优先使用简洁明确的术语  
3. **标准性原则**: 遵循行业标准和Git术语习惯
4. **可读性原则**: 术语应该易于理解和记忆
5. **扩展性原则**: 术语体系应支持未来功能扩展

---

**📝 说明**: 本术语表是 NewGPF 项目的标准参考，所有文档编写和代码实现都应遵循此术语规范。如需添加新术语，请更新本文档并通知所有项目成员。