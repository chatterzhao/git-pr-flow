# 开发指南

## GPF
GPF (Git PR Flow) Cli 工具是一个结合 Epic 开发流程、Git Worktree 和 GitHub Cli 设计的 PR 友好工具，通过 gpf status，gpf start，gpf sync，gpf pr，gpf clean 五个命令实现从创建分支到清理分支的完整PR流程：
- **Epic开发流程**让应用拆分分为多个Epic大功能，每个Epic拆分为多个独立的Epic的子Feature，每个Feature开发完成，创建一个Feature→Epic的PR，确保PR功能集中、职责单一、变更可控。当Epic开发完成或达到一个里程碑，创建一个Epic→Develop的PR，这种Feature→Epic→Develop的分层合并策略让代码审查更聚焦，避免了传统开发中"巨型PR"和"功能混杂"的问题；
- **Git Worktree物理隔离技术**实现多个功能的真正并行开发（多AI并行开发很方便）。开发者只需通过cd命令切换Worktree目录就能无缝切换到对应git分支（git worktree 特性，不需要 git checkout命令），不同worktree目录物理隔离，彻底避免传统Git工作流中的分支冲突、环境污染和状态混乱问题；
- **GitHub CLI工具**gh工具可以在本地操作PR，让开发者能够在本地完成相关的操作；
- **智能环境感知**：根据命令自动切换目录、智能补全输入的前缀`epic-`和后缀`-e|-ef`

**gpf工具操作逻辑**：
使用5个命令，背后的逻辑为：
- **创建 Epic 与 Epic Feature 分支**：`gpf start -e|-ef <epic-name或epic-name-feature-name> <branch>`创建后会进入对应目录，可在终端使用 `pwd` 命令查看，如果目录位置不对，请使用 `cd` 命令进入正确的目录，注意除维护 docs/epic-roadmap/ 目录下的 roadmap 文档外 epic 分支不允许提交，也就是开发需要在 epic 的子 feature 分支进行。
- **epic feature 分支和 epic 分支都推送到 GitHub**：在对应目录执行`gpf pr`或`gpf pr <epic-feature>`或`gpf pr <epic>` 这样则 push 和 pr 对应的分支 
- **PR时机**：每个 Epic 的子 Feature 开发完成则 push 和 pr 到 Epic；Epic 达到一定里程碑后 push 和 PR 到 Develop 分支
- **gpf 命令下到上只能 pr review，没有本地分支merge操作**：
  1. Epic-Feature 合并到 Epic：push -> Epic-Feature -> pr -> Epic -> review -> 可清理 Epic-Feature 本地 worktree 目录和本地、远程分支，通过 **gpf pr** 完成；
  2. Epic 合并到 develop：push -> Epic -> pr -> Develop -> review -> 可清理 Epic 本地 worktree 目录和本地、远程分支，通过 **gpf pr** 完成
- **gpf 命令上到下只能 pull merge，没有本地分支直接merge操作**：pull -> Develop -> Epic -> merge -> Epic-Feature -> merge， 通过 **gpf sync** 命令完成

## 严格遵守架构指南
架构指南 ARCHITECTURE.md
### 严格分层原则
  - **命令层**：只能调用模块层方法，绝不跨层调用 lib/commands (注意它不在 core 目录下)
  - **模块层**：只能调用组合层方法，提供完整业务功能 lib/core/modules
  - **组合层**：只能调用原子层方法，组合基础功能单元 lib/core/composite
  - **原子层**：不依赖任何GPF内部层，提供最基础的功能 lib/core atomic
  - **功能不足时**：回到对应Epic的Feature补充，而非跨层调用

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