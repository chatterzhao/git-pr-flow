# gpf-ready-fixes

## 本epic的职责:

修复 `gpf ready` 命令的命名规则不一致和功能范围限制问题，实现与其他命令统一的Epic名称简化支持和Epic级别就绪检查功能，确保命令符合AI友好设计原则。

## 关键问题分析：

基于 `docs/analysis/command-analysis-report.md` 的分析，gpf ready命令存在以下问题：

### 🚨 主要问题：
1. **命名规则不一致**: 与其他命令不同，ready命令不支持Epic名称简化
2. **功能范围限制**: 仅支持功能分支检查，不支持Epic级别检查
3. **用户体验割裂**: 无法使用`gpf ready documentation-review`检查整个Epic

### 🎯 改进目标：
1. 统一命名规则，支持Epic名称简化输入
2. 扩展功能范围，支持Epic级别就绪检查
3. 智能参数判断，自动识别Epic vs 功能分支
4. 保持现有优秀的上下文智能检测机制

## 计划有哪些子功能

### 子功能1：unified-naming-support

**创建命令：** `gpf start gpf-ready-fixes/unified-naming-support`

**功能描述：**
实现与其他命令一致的Epic名称简化支持，支持`gpf ready epic-name`自动匹配Epic级别检查

#### 验收标准：
- [ ] `gpf ready documentation-review`自动匹配Epic检查
- [ ] 保持向后兼容性，现有功能分支格式继续工作
- [ ] 错误提示包含Epic名称简化说明
- [ ] 与gpf init、gpf start、gpf status命令保持一致的命名处理

---

### 子功能2：epic-level-readiness-check

**创建命令：** `gpf start gpf-ready-fixes/epic-level-readiness-check`

**功能描述：**
完善Epic级别的就绪检查功能，智能参数判断Epic vs 功能分支检查范围

#### 验收标准：
- [ ] 支持`gpf ready epic-name`执行Epic级别检查
- [ ] 智能参数解析：包含`/`的为功能分支，不包含的为Epic
- [ ] Epic检查包含所有子功能的就绪状态汇总
- [ ] 生成Epic级别的就绪报告

---

### 子功能3：enhanced-error-handling

**创建命令：** `gpf start gpf-ready-fixes/enhanced-error-handling`

**功能描述：**
优化错误处理和用户提示，提供更友好的AI学习体验

#### 验收标准：
- [ ] 参数格式错误时提供清晰的命令示例
- [ ] Epic不存在时显示可用Epic列表
- [ ] 错误信息包含具体的解决方案指引
- [ ] 支持AI工具理解的结构化错误信息

---

**创建时间：** 2025-06-30 17:45:00  
**基础分支：** develop