# gpf-pr-fixes

## 本epic的职责:

改进 `gpf pr` 命令的AI友好性和用户体验，解决强制确认机制、命名规则不一致和错误处理等问题，实现真正的智能自动化PR创建功能。

## 关键问题分析：

基于 `docs/analysis/command-analysis-report.md` 的分析，gpf pr命令存在以下问题：

### 🚨 主要问题：
1. **强制确认机制**: 无条件的确认要求，不符合AI友好设计
2. **命名规则不一致**: 仅支持功能分支，不支持Epic名称简化输入
3. **错误处理不够友好**: Epic检测失败时提示不够明确

### 🎯 改进目标：
1. 实现智能条件判断，去除强制确认机制
2. 统一命名规则，支持Epic级别PR创建
3. 优化错误处理，提供具体可操作的建议
4. 保持现有优秀的上下文智能检测和自动化功能

## 计划有哪些子功能

### 子功能1：smart-confirmation-logic

**创建命令：** `gpf start gpf-pr-fixes/smart-confirmation-logic`

**功能描述：**
实现智能确认逻辑，替换强制确认机制，使AI工具能够自动创建PR

#### 验收标准：
- [ ] 在功能分支目录中且ready检查通过时，直接创建PR无需确认
- [ ] 参数完整且分支就绪时，直接执行无需确认
- [ ] 仅在模糊情况或存在问题时才提示确认
- [ ] 保持安全性：检测未提交更改、分支冲突等风险情况
- [ ] 支持--force参数强制跳过所有确认

---

### 子功能2：unified-naming-support

**创建命令：** `gpf start gpf-pr-fixes/unified-naming-support`

**功能描述：**
实现与其他命令一致的Epic名称简化支持，支持Epic级别PR创建

#### 验收标准：
- [ ] 支持`gpf pr epic-name`创建Epic→develop的PR
- [ ] 支持`gpf pr epic-name/feature-name`创建功能→Epic的PR
- [ ] 智能参数解析：包含`/`为功能分支，不包含为Epic
- [ ] 保持向后兼容性，现有功能分支格式继续工作
- [ ] 与gpf init、gpf start、gpf status、gpf ready命令保持一致

---

### 子功能3：enhanced-error-handling

**创建命令：** `gpf start gpf-pr-fixes/enhanced-error-handling`

**功能描述：**
优化错误处理和用户提示，提供更友好的AI学习体验

#### 验收标准：
- [ ] Epic检测失败时提供具体的解决步骤
- [ ] 工作目录不存在时提供`gpf start`命令示例
- [ ] 分支不存在时显示可用分支列表和建议
- [ ] 依赖关系问题时提供具体的解决方案
- [ ] 错误信息包含上下文相关的可操作建议

---

**创建时间：** 2025-06-30 07:22:54  
**基础分支：** develop