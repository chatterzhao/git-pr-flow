# git-hooks-optimization

## 本epic的职责:

优化Git hooks拦截机制，实现更精准的工作流保护：

- [ ] 允许Epic分支提交roadmap相关文件（docs/epic/*.md）
- [ ] 优化Epic提交拦截的引导信息，提供清晰的解决方案  
- [ ] 允许Epic分支提交配置和文档类修改

## 计划有哪些子功能

### 子功能1：roadmap-commit-allowlist

**创建命令：** `gpf start git-hooks-optimization/roadmap-commit-allowlist`

**功能描述：**
允许Epic分支提交roadmap文档，实现精准的白名单机制

#### 验收标准：
- [ ] Epic分支可以提交docs/epic/目录下的.md文件
- [ ] 其他文件修改仍被正确拦截
- [ ] 提供清晰的拦截引导信息

---

### 子功能2：enhanced-guidance-messages

**创建命令：** `gpf start git-hooks-optimization/enhanced-guidance-messages`

**功能描述：**
优化Git hooks拦截时的引导信息，帮助用户理解正确的工作流

#### 验收标准：
- [ ] 拦截信息包含为什么被拦截的原因
- [ ] 提供创建子功能的具体步骤
- [ ] 说明如何将Epic修改移动到子功能分支
- [ ] 提供合并流程的引导

---

### 子功能3：config-docs-allowlist

**创建命令：** `gpf start git-hooks-optimization/config-docs-allowlist`

**功能描述：**
允许Epic分支提交配置和文档类文件的合理修改

#### 验收标准：
- [ ] 允许.git-pr-flow.yaml等配置文件修改
- [ ] 允许README.md等文档文件修改
- [ ] 保持代码文件的严格拦截

---

**创建时间：** 2025-06-29 18:49:42  
**基础分支：** develop
