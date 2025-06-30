# gpf-status-fixes

## 本epic的职责:

修复 `gpf status` 命令的重大设计问题，实现完整的参数解析、命名规则统一和JSON API支持，确保命令符合AI友好设计原则。

## 关键问题分析：

基于 `docs/analysis/command-analysis-report.md` 的分析，gpf status命令存在以下严重问题：

### 🚨 严重问题：
1. **完全缺失参数解析**: `--json`, `--help`等选项被误解释为Epic名称
2. **命名规则不一致**: 不支持Epic名称简化，违反GPF原则
3. **文档与实现不符**: docs/API.md定义的JSON功能完全未实现
4. **缺少JSON API支持**: AI工具无法获得结构化输出

### 🎯 改进目标：
1. 重写参数解析逻辑，支持选项和参数
2. 统一命名规则，支持Epic名称自动匹配
3. 实现完整的JSON API功能
4. 提供上下文智能检测和用法帮助

## 计划有哪些子功能

### 子功能1：rewrite-parameter-parsing

**创建命令：** `gpf start gpf-status-fixes/rewrite-parameter-parsing`

**功能描述：**
重写参数解析逻辑，支持选项（--json, --help）和Epic名称参数的正确识别

#### 验收标准：
- [ ] `--json`选项不再被误解释为Epic名称
- [ ] 支持`--help`显示用法帮助
- [ ] 正确区分选项和Epic名称参数
- [ ] 保持向后兼容性

---

### 子功能2：implement-json-api

**创建命令：** `gpf start gpf-status-fixes/implement-json-api`

**功能描述：**
实现完整的JSON API功能，提供结构化的状态输出

#### 验收标准：
- [ ] `gpf status --json`输出结构化JSON数据
- [ ] `gpf status <epic-name> --json`输出特定Epic的JSON数据
- [ ] JSON格式符合docs/API.md规范
- [ ] 包含仓库状态、Epic状态、功能分支等完整信息

---

### 子功能3：unified-naming-rules

**创建命令：** `gpf start gpf-status-fixes/unified-naming-rules`

**功能描述：**
统一命名规则，支持Epic名称简化输入和自动匹配

#### 验收标准：
- [ ] `gpf status documentation-review`自动匹配`epic/documentation-review`
- [ ] 支持部分匹配和智能建议
- [ ] 错误提示包含可能的匹配Epic
- [ ] 与其他命令保持一致的命名处理

---

### 子功能4：context-intelligent-detection

**创建命令：** `gpf start gpf-status-fixes/context-intelligent-detection`

**功能描述：**
实现上下文智能检测，根据当前目录和分支自动判断显示内容

#### 验收标准：
- [ ] 在Epic目录中自动显示该Epic状态
- [ ] 在功能目录中自动显示该功能状态
- [ ] 在根目录中显示全局概览
- [ ] 无参数时提供智能默认行为

---

**创建时间：** 2025-06-30 17:00:00  
**基础分支：** develop
