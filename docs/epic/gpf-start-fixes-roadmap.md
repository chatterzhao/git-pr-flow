# gpf-start-fixes

## 本epic的职责:

修复 `gpf start` 命令的智能分支创建逻辑，确保在任何环境下都能正确基于Epic分支创建子功能分支。

### 🚨 当前问题分析：

1. 用户输入 `gpf start xx/yy` 时存在语法错误
2. start命令没有正确处理epic目录切换
3. 没有验证epic是否存在就尝试创建功能分支

### 🎯 改进目标：

**AI友好性设计原则：**
- [ ] **无交互执行**：`start xx/yy` 命令应该自动推断并执行，不需要用户选择
- [ ] **智能错误引导**：出错时提供智能建议，包括拼写检查、可用选项、下一步操作
- [ ] **参数化支持**：命令支持带参数执行，减少交互式选择

**核心功能要求：**
- [ ] **Epic自动识别**：从 `start xx/yy` 自动提取xx作为epic-name
- [ ] **强制Epic切换**：自动切换到 `.worktrees/epic--xx` 目录执行
- [ ] **智能验证**：检查epic/xx分支和epic--xx目录是否存在
- [ ] **基于Epic创建**：创建的 `xx/yy` 分支必须基于 `epic/xx` 分支
- [ ] **智能错误处理**：
  - Epic不存在时提供拼写建议
  - 列出当前可用的epic
  - 引导用户使用 `gpf init <epic-name>` 创建
- [ ] **ui_select_menu修复**：修复stdout/stderr输出问题

## 计划有哪些子功能

### 子功能1：ui-select-menu-fix

**创建命令：** `gpf start gpf-start-fixes/ui-select-menu-fix`

**功能描述：**
修复ui_select_menu函数的stdout/stderr输出问题，解决语法错误

#### 验收标准：
- [ ] 修复ui_select_menu函数将菜单显示输出到stderr
- [ ] 确保只有选择结果输出到stdout
- [ ] 修复read命令的输出重定向
- [ ] 测试选择菜单不再产生语法错误

---

### 子功能2：epic-directory-switching

**创建命令：** `gpf start gpf-start-fixes/epic-directory-switching`

**功能描述：**
实现强制的epic目录切换逻辑，确保start命令必须在正确的epic目录中执行

#### 验收标准：
- [ ] 从用户输入xx/yy中提取epic名称xx
- [ ] 检查.worktrees/epic--xx目录是否存在
- [ ] 检查epic/xx分支是否存在
- [ ] 如果epic存在，强制cd到epic目录并重新执行命令
- [ ] 如果epic不存在，提示用户错误信息
- [ ] 实现AI友好的无交互执行模式

---

### 子功能3：epic-validation-and-error-handling

**创建命令：** `gpf start gpf-start-fixes/epic-validation-and-error-handling`

**功能描述：**
完善epic验证和错误处理逻辑，提供AI友好的智能引导

#### 验收标准：
- [ ] 提供epic不存在时的详细错误信息
- [ ] 实现epic名称拼写检查和建议
- [ ] 列出当前可用的epic列表
- [ ] 提供相似名称建议（模糊匹配）
- [ ] 引导用户使用 `gpf init <epic-name>` 创建新epic
- [ ] 确保错误信息对AI和人类都友好

---

**创建时间：** 2025-06-30 20:29:52  
**基础分支：** develop

---

## 测试标记
这是一个测试标记，用于验证分支基础关系。如果新创建的功能分支能看到这个标记，说明确实基于Epic分支创建。