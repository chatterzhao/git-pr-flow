# 开发指南

## 严格遵守架构指南
架构指南 ARCHITECTURE.md

## roadmap 驱动开发

### 文档驱动开发
先阅读之前的 roadmap，根据 roadmap 先阅读所有文档，先验证 roadmap 是否准确，然后根据 roadmap 理解开发内容，确定下一步任务，并更新 roadmap；

### roadmap 设计的开发流程
- roadmap 遵循 Epic 开发流程，规划创建什么Epic，然后再规划它的子Feature，制定验收标准
- roadmap 遵循 git worktree 创建对应的 Epic 工作目录，和 Epic 的子 Feature 工作目录

## 测试驱动开发
充分理解了 roadmap，然后先写测试，再写代码，代码实现后进行测试，通过后更新 roadmap 和 相关文档，比如示例代码变化了的（注意示例代码是伪代码即可，不要完全跟实际一样）

## 在合适的位置测试和修复，在合适的位置正式修复和提交
测试场景有，epic feature, epic, develop
假如是合并到了 develop，那测试不通过时，不是去 epic feature 修复，然后一路合并到 develop 再测试，不通过又循环，而是临时直接在develop 修复并测试：
1. develop分支测试 → 发现问题，快速验证解决方案
2. epic feature分支修复 → 在正确的分支中正式实现修复
3. develop分支restore → 清理临时修改
4. 提交合并 → 正式合并修复