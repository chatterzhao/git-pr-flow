# Git PR Flow 架构设计

> 系统架构和技术实现 - 面向架构师和高级开发者

## 快速导航

- 📖 **[项目介绍](README.md)** - 了解项目目标和核心价值  
- 🔧 **[开发指南](DEVELOPMENT.md)** - 贡献代码和开发环境
- 📘 **[API文档](API.md)** - 命令行接口参考
- 🎨 **[交互设计](UX.md)** - 用户体验设计

## 总体架构

### 系统层次
```
┌─────────────────────────────────────┐
│           用户接口层 (CLI)            │
├─────────────────────────────────────┤
│           命令处理层                  │
├─────────────────────────────────────┤
│           核心业务层                  │
├─────────────────────────────────────┤
│           Git 抽象层                 │
├─────────────────────────────────────┤
│           系统工具层                  │
└─────────────────────────────────────┘
```

### 核心组件关系
```
git-pr (入口)
    ├── 命令路由器 (command_router)
    ├── 配置管理器 (config_manager)
    ├── 状态管理器 (state_manager)
    ├── 同步引擎 (sync_engine)
    ├── 工作树管理器 (worktree_manager)
    ├── 冲突解决器 (conflict_resolver)
    ├── 交互界面 (ui_manager)
    └── Git 包装器 (git_wrapper)
```

## 模块详细设计

### 1. 入口模块 (bin/git-pr)

**职责**: 命令行解析、环境检查、模块加载

```bash
#!/bin/bash
set -euo pipefail

# 全局变量
declare -g GIT_PR_VERSION="1.0.0"
declare -g GIT_PR_ROOT
declare -g GIT_PR_CONFIG
declare -g GIT_PR_DEBUG="${GIT_PR_DEBUG:-0}"

# 模块加载
source_modules() {
  local lib_dir="$GIT_PR_ROOT/lib"
  
  # 核心工具类
  source "$lib_dir/utils/common.sh"
  source "$lib_dir/utils/git.sh"
  source "$lib_dir/utils/ui.sh"
  source "$lib_dir/utils/config.sh"
  
  # 核心业务类
  source "$lib_dir/core/init.sh"
  source "$lib_dir/core/status.sh"
  source "$lib_dir/core/sync.sh"
  source "$lib_dir/core/worktree.sh"
  
  # 命令处理器
  source "$lib_dir/commands/init.sh"
  source "$lib_dir/commands/start.sh"
  source "$lib_dir/commands/status.sh"
  source "$lib_dir/commands/sync.sh"
  source "$lib_dir/commands/clean.sh"
}

# 命令解析
parse_command() {
  local command="${1:-}"
  shift || true
  
  case "$command" in
    "init")
      if [[ $# -eq 0 ]]; then
        # 无参数：列出现有Epic配置或引导创建
        handle_init_interactive
      else
        # 有参数：直接初始化指定Epic
        handle_init "$1"
      fi
      ;;
    "start")
      if [[ $# -eq 0 ]]; then
        # 无参数：列出现有子功能分支或引导创建
        handle_start_interactive  
      else
        # 有参数：直接创建指定子功能
        handle_start "$1"
      fi
      ;;
    "status"|"sync"|"pr"|"ready"|"clean")
      # 其他命令保持原有行为
      "handle_$command" "$@"
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

# 主函数
main() {
  init_environment
  source_modules
  parse_command "$@"
}
```

### 1.5. 交互式命令处理器 (commands/interactive.sh)

**职责**: 无参数命令的交互式处理逻辑

```bash
# Epic交互式初始化
handle_init_interactive() {
  ui_info "检测现有Epic配置..."
  
  local existing_epics
  existing_epics=($(find_existing_epics))
  
  if [[ ${#existing_epics[@]} -eq 0 ]]; then
    ui_info "未发现现有Epic配置，开始创建新Epic"
    prompt_new_epic_creation
  else
    show_existing_epics "${existing_epics[@]}"
    
    local choices=(
      "创建新的Epic功能"
      $(printf "重新配置 %s\n" "${existing_epics[@]}")
      "查看Epic详情"
    )
    
    local choice
    choice=$(ui_select "选择操作:" "${choices[@]}")
    
    case "$choice" in
      "创建新的Epic功能")
        prompt_new_epic_creation
        ;;
      "重新配置 "*)
        local epic_name="${choice#重新配置 }"
        handle_init "$epic_name"
        ;;
      "查看Epic详情")
        show_epic_details_interactive "${existing_epics[@]}"
        ;;
    esac
  fi
}

# 子功能交互式开始
handle_start_interactive() {
  local current_epic
  current_epic=$(detect_current_epic)
  
  if [[ -z "$current_epic" ]]; then
    ui_error "未检测到当前Epic环境，请先运行 git-pr-flow init"
    return 1
  fi
  
  ui_info "当前Epic环境: $current_epic"
  
  local existing_branches
  existing_branches=($(list_epic_branches "$current_epic"))
  
  if [[ ${#existing_branches[@]} -gt 0 ]]; then
    show_existing_branches "$current_epic" "${existing_branches[@]}"
  fi
  
  local choices=(
    "创建新的子功能"
    $(printf "切换到 %s\n" "${existing_branches[@]}")
    "查看分支详情"
    "切换到其他Epic"
  )
  
  local choice
  choice=$(ui_select "选择操作:" "${choices[@]}")
  
  case "$choice" in
    "创建新的子功能")
      prompt_new_branch_creation "$current_epic"
      ;;
    "切换到 "*)
      local branch_name="${choice#切换到 }"
      switch_to_branch "$branch_name"
      ;;
    "查看分支详情")
      show_branch_details_interactive "${existing_branches[@]}"
      ;;
    "切换到其他Epic")
      switch_epic_interactive
      ;;
  esac
}

# Epic发现和列举
find_existing_epics() {
  # 查找所有.git-pr-flow.yaml配置文件或git配置中的Epic
  local epics=()
  
  # 从配置文件读取
  if [[ -f ".git-pr-flow.yaml" ]]; then
    local epic_name
    epic_name=$(config_file_get "epic_name")
    [[ -n "$epic_name" ]] && epics+=("$epic_name")
  fi
  
  # 从git配置读取其他Epic
  local git_epics
  git_epics=($(git config --get-regexp '^pr\.epic\.' | cut -d. -f3 | sort -u))
  epics+=("${git_epics[@]}")
  
  # 去重并输出
  printf '%s\n' "${epics[@]}" | sort -u
}

# 显示现有Epic概览
show_existing_epics() {
  local epics=("$@")
  
  ui_info "已有Epic配置:"
  for epic in "${epics[@]}"; do
    local description base_branch worktree_path created_time
    description=$(get_epic_description "$epic")
    base_branch=$(get_epic_base_branch "$epic") 
    worktree_path=$(get_epic_worktree_path "$epic")
    created_time=$(get_epic_created_time "$epic")
    
    echo "├─ $epic ($description) - 创建于$created_time"
    echo "│   └─ 基础分支: $base_branch, 工作树: $worktree_path"
  done
}

# 显示现有分支概览
show_existing_branches() {
  local epic="$1"
  shift
  local branches=("$@")
  
  ui_info "现有子功能分支:"
  
  local completed=() developing=()
  
  for branch in "${branches[@]}"; do
    local status
    status=$(get_branch_status "$branch")
    local commits last_update
    commits=$(get_branch_commit_count "$branch")
    last_update=$(get_branch_last_update "$branch")
    
    if [[ "$status" == "completed" ]]; then
      completed+=("$branch ($commits个提交) - 最后更新: $last_update")
    else
      developing+=("$branch ($commits个提交) - 最后更新: $last_update")
    fi
  done
  
  if [[ ${#completed[@]} -gt 0 ]]; then
    echo "✅ 已完成:"
    printf '├─ %s\n' "${completed[@]}"
  fi
  
  if [[ ${#developing[@]} -gt 0 ]]; then
    echo "🔄 开发中:"  
    printf '├─ %s\n' "${developing[@]}"
  fi
}
```

### 2. 配置管理器 (utils/config.sh)

**职责**: 配置文件读写、默认值管理、验证

```bash
# 配置文件层次
# 1. 系统默认配置 (内置)
# 2. 全局用户配置 (~/.gitprconfig)
# 3. 项目Git配置 (.git/pr-config)
# 4. Epic配置文件 (.git-pr-flow.yaml) ← 新增
# 5. 环境变量覆盖
# 6. 命令行参数覆盖

declare -A CONFIG_DEFAULTS=(
  ["core.epic_dir"]="@epics"
  ["core.temp_dir"]="@temp"
  ["sync.default_scope"]="deps"
  ["sync.conflict_mode"]="prompt"
  ["sync.cleanup_policy"]="ask"
  ["ui.color"]="auto"
  ["ui.ascii_tree"]="true"
)

# Epic配置文件管理
declare -g CONFIG_FILE=".git-pr-flow.yaml"

config_file_exists() {
  [[ -f "$CONFIG_FILE" ]]
}

config_file_load() {
  if ! config_file_exists; then
    return 1
  fi
  
  # 使用yq或手动解析YAML
  if command -v yq >/dev/null; then
    CONFIG_DATA=$(yq eval '.' "$CONFIG_FILE")
  else
    # 简单的YAML解析器 (仅支持键值对)
    CONFIG_DATA=$(parse_yaml_simple "$CONFIG_FILE")
  fi
  
  return 0
}

config_file_get() {
  local key="$1"
  local default="${2:-}"
  
  if ! config_file_exists; then
    echo "$default"
    return
  fi
  
  # 从配置文件读取值
  if command -v yq >/dev/null; then
    local value
    value=$(yq eval ".$key" "$CONFIG_FILE" 2>/dev/null)
    if [[ "$value" != "null" && -n "$value" ]]; then
      echo "$value"
    else
      echo "$default"
    fi
  else
    # 简单匹配
    grep "^$key:" "$CONFIG_FILE" | cut -d':' -f2- | sed 's/^ *//' || echo "$default"
  fi
}

config_file_set() {
  local key="$1"
  local value="$2"
  
  # 如果配置文件不存在，创建新文件
  if ! config_file_exists; then
    cat > "$CONFIG_FILE" <<EOF
# Git PR Flow 配置文件
# 自动生成于 $(date -Iseconds)
config_version: "1.0"
EOF
  fi
  
  # 更新配置值
  if command -v yq >/dev/null; then
    yq eval ".$key = \"$value\"" -i "$CONFIG_FILE"
  else
    # 简单的替换或追加
    if grep -q "^$key:" "$CONFIG_FILE"; then
      sed -i.bak "s|^$key:.*|$key: $value|" "$CONFIG_FILE"
      rm -f "$CONFIG_FILE.bak"
    else
      echo "$key: $value" >> "$CONFIG_FILE"
    fi
  fi
}

config_file_create_epic() {
  local epic_name="$1"
  local description="$2"
  local base_branch="$3"
  local worktree_path="$4"
  
  cat > "$CONFIG_FILE" <<EOF
# Git PR Flow Epic 配置
# Epic: $epic_name
# 创建时间: $(date -Iseconds)

epic_name: $epic_name
description: $description
base_branch: $base_branch
architecture: complete
epic_branch: epic/$epic_name
worktree_path: $worktree_path
workflow_type: gitflow
created_at: $(date -Iseconds)
config_version: "1.0"
EOF
  
  ui_success "配置文件已创建: $CONFIG_FILE"
}

config_file_validate() {
  if ! config_file_exists; then
    return 1
  fi
  
  # 检查必需字段
  local required_fields=("epic_name" "base_branch" "epic_branch" "worktree_path")
  
  for field in "${required_fields[@]}"; do
    local value
    value=$(config_file_get "$field")
    if [[ -z "$value" ]]; then
      ui_error "配置文件缺少必需字段: $field"
      return 1
    fi
  done
  
  # 检查配置版本
  local config_version
  config_version=$(config_file_get "config_version")
  if [[ "$config_version" != "1.0" ]]; then
    ui_warning "配置文件版本不匹配: $config_version (期望: 1.0)"
  fi
  
  return 0
}

# 传统配置管理（向后兼容）
config_get() {
  local key="$1"
  local default="${2:-}"
  
  # 优先级: 环境变量 > Epic配置文件 > 项目配置 > 全局配置 > 默认值
  local env_key="GIT_PR_${key//.//_}"
  env_key="${env_key^^}"
  
  if [[ -n "${!env_key:-}" ]]; then
    echo "${!env_key}"
  elif config_file_exists && [[ "$key" =~ ^(epic_|base_|worktree_|description) ]]; then
    # Epic相关配置优先从配置文件读取
    config_file_get "$key" "$default"
  elif [[ -f ".git/pr-config" ]]; then
    git config -f .git/pr-config --get "pr.$key" 2>/dev/null || \
    git config --global --get "pr.$key" 2>/dev/null || \
    echo "${CONFIG_DEFAULTS[$key]:-$default}"
  else
    git config --global --get "pr.$key" 2>/dev/null || \
    echo "${CONFIG_DEFAULTS[$key]:-$default}"
  fi
}

config_set() {
  local key="$1"
  local value="$2"
  local scope="${3:-project}"  # project|global|epic
  
  case "$scope" in
    "epic")
      config_file_set "$key" "$value"
      ;;
    "project")
      git config -f .git/pr-config "pr.$key" "$value"
      ;;
    "global")
      git config --global "pr.$key" "$value"
      ;;
  esac
}

# YAML解析器 (简化版)
parse_yaml_simple() {
  local yaml_file="$1"
  
  # 基本的键值对解析，忽略嵌套结构
  grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' "$yaml_file" | \
  while IFS=':' read -r key value; do
    # 去掉前后空格
    key=$(echo "$key" | sed 's/^ *//;s/ *$//')
    value=$(echo "$value" | sed 's/^ *//;s/ *$//')
    # 去掉引号
    value=$(echo "$value" | sed 's/^["'"'"']//;s/["'"'"']$//')
    echo "$key=$value"
  done
}
```

### 3. 状态管理器 (core/status.sh)

**职责**: 分支状态检查、依赖关系计算、状态缓存

```bash
declare -A BRANCH_CACHE
declare -A DEPENDENCY_CACHE

# 分支状态数据结构
# {
#   "name": "auth/login",
#   "status": "ready|draft|conflict",
#   "dependencies": ["main"],
#   "dependents": ["auth/register", "auth/2fa"],
#   "commits_ahead": 3,
#   "commits_behind": 0,
#   "worktree_path": "/path/to/.worktrees/auth--login",
#   "last_sync": "2024-01-01T10:00:00Z"
# }

get_branch_status() {
  local branch="$1"
  local cache_key="status:$branch"
  
  # 检查缓存
  if [[ -n "${BRANCH_CACHE[$cache_key]:-}" ]]; then
    echo "${BRANCH_CACHE[$cache_key]}"
    return
  fi
  
  local status_data
  status_data=$(calculate_branch_status "$branch")
  
  # 缓存结果
  BRANCH_CACHE[$cache_key]="$status_data"
  echo "$status_data"
}

calculate_branch_status() {
  local branch="$1"
  
  # 计算提交差异
  local ahead behind
  ahead=$(git rev-list --count "@{upstream}..$branch" 2>/dev/null || echo "0")
  behind=$(git rev-list --count "$branch..@{upstream}" 2>/dev/null || echo "0")
  
  # 检查工作树状态
  local worktree_path
  worktree_path=$(get_worktree_path "$branch")
  
  # 检查冲突状态
  local has_conflicts
  has_conflicts=$(check_potential_conflicts "$branch")
  
  # 构建状态JSON
  cat <<EOF
{
  "name": "$branch",
  "status": "$(determine_status "$branch" "$has_conflicts")",
  "commits_ahead": $ahead,
  "commits_behind": $behind,
  "worktree_path": "$worktree_path",
  "has_conflicts": $has_conflicts
}
EOF
}

# 依赖关系计算
get_dependencies() {
  local branch="$1"
  local cache_key="deps:$branch"
  
  if [[ -n "${DEPENDENCY_CACHE[$cache_key]:-}" ]]; then
    echo "${DEPENDENCY_CACHE[$cache_key]}"
    return
  fi
  
  local deps
  deps=$(calculate_dependencies "$branch")
  DEPENDENCY_CACHE[$cache_key]="$deps"
  echo "$deps"
}

calculate_dependencies() {
  local branch="$1"
  
  # 从配置中读取显式依赖
  local explicit_deps
  explicit_deps=$(config_get "branch.$branch.depends" "")
  
  # 自动检测依赖（基于分支创建历史）
  local auto_deps
  auto_deps=$(detect_auto_dependencies "$branch")
  
  # 合并去重
  echo "$explicit_deps $auto_deps" | tr ' ' '\n' | sort -u | tr '\n' ' '
}
```

### 4. 同步引擎 (core/sync.sh)

**职责**: 依赖同步、冲突检测、批量操作

```bash
# 同步策略枚举
declare -r SYNC_CURRENT="current"
declare -r SYNC_DEPS="deps"
declare -r SYNC_EPIC="epic"

# 同步执行计划
# {
#   "target_branches": ["auth/register", "auth/2fa"],
#   "source_branch": "auth/login",
#   "operations": [
#     {"type": "merge", "from": "auth/login", "to": "auth/register"},
#     {"type": "merge", "from": "auth/login", "to": "auth/2fa"}
#   ],
#   "potential_conflicts": ["src/auth/utils.js"],
#   "worktree_switches": [
#     {"branch": "auth/register", "path": "/path/to/.worktrees/auth--register"}
#   ]
# }

sync_with_strategy() {
  local strategy="$1"
  local force="${2:-false}"
  
  # 生成同步计划
  local sync_plan
  sync_plan=$(generate_sync_plan "$strategy" "$force")
  
  # 显示计划预览
  if ! preview_sync_plan "$sync_plan"; then
    ui_error "用户取消同步操作"
    return 1
  fi
  
  # 执行同步计划
  execute_sync_plan "$sync_plan"
}

generate_sync_plan() {
  local strategy="$1"
  local force="$2"
  
  local current_branch
  current_branch=$(git_current_branch)
  
  local target_branches
  case "$strategy" in
    "$SYNC_CURRENT")
      target_branches=("$current_branch")
      ;;
    "$SYNC_DEPS")
      target_branches=($(get_dependent_branches "$current_branch"))
      ;;
    "$SYNC_EPIC")
      target_branches=($(get_epic_branches "$current_branch"))
      ;;
  esac
  
  # 过滤ready状态分支
  if [[ "$force" != "true" ]]; then
    target_branches=($(filter_ready_branches "${target_branches[@]}"))
  fi
  
  # 检测冲突
  local potential_conflicts
  potential_conflicts=($(detect_batch_conflicts "${target_branches[@]}"))
  
  # 构建执行计划JSON
  build_sync_plan_json "$current_branch" "${target_branches[@]}"
}

execute_sync_plan() {
  local plan_json="$1"
  
  # 解析计划
  local operations
  operations=$(echo "$plan_json" | jq -r '.operations[] | @base64')
  
  local success_count=0
  local total_count
  total_count=$(echo "$operations" | wc -l)
  
  # 执行每个操作
  while IFS= read -r operation_b64; do
    local operation
    operation=$(echo "$operation_b64" | base64 -d)
    
    local op_type from_branch to_branch
    op_type=$(echo "$operation" | jq -r '.type')
    from_branch=$(echo "$operation" | jq -r '.from')
    to_branch=$(echo "$operation" | jq -r '.to')
    
    ui_info "同步 $from_branch → $to_branch"
    
    if execute_sync_operation "$op_type" "$from_branch" "$to_branch"; then
      ((success_count++))
      ui_success "✔ $to_branch 同步完成"
    else
      ui_error "✗ $to_branch 同步失败"
      # 是否继续？
      if ! ui_confirm "继续同步其他分支？"; then
        break
      fi
    fi
  done <<< "$operations"
  
  ui_info "同步完成: $success_count/$total_count"
}

execute_sync_operation() {
  local op_type="$1"
  local from_branch="$2"
  local to_branch="$3"
  
  # 切换到目标分支工作树
  local worktree_path
  worktree_path=$(get_worktree_path "$to_branch")
  
  if [[ -n "$worktree_path" ]]; then
    cd "$worktree_path"
  fi
  
  # 执行合并操作
  case "$op_type" in
    "merge")
      git checkout "$to_branch" && \
      git merge "$from_branch" --no-edit
      ;;
    "rebase")
      git checkout "$to_branch" && \
      git rebase "$from_branch"
      ;;
  esac
}
```

### 5. 工作树管理器 (core/worktree.sh)

**职责**: 工作树创建、清理、路径管理

```bash
# 工作树布局（新架构：分支名直接映射）
# .worktrees/
# ├── auth--login/        # auth/login分支工作树
# ├── auth--register/     # auth/register分支工作树 
# ├── auth--2fa/          # auth/2fa分支工作树
# ├── payment--checkout/  # payment/checkout分支工作树
# ├── payment--refund/    # payment/refund分支工作树
# └── hotfix--bug-123/    # hotfix/bug-123分支工作树
#
# 规则：分支名的 / 转换为目录名的 --

create_epic_worktree() {
  local epic_name="$1"
  local branch_name="$2"
  
  local epic_dir
  epic_dir="$(config_get "core.epic_dir")/$epic_name"
  
  # 检查是否已存在
  if [[ -d "$epic_dir" ]]; then
    ui_info "Epic工作树已存在: $epic_dir"
    switch_to_branch_in_worktree "$epic_dir" "$branch_name"
    return
  fi
  
  # 创建Epic工作树
  ui_info "创建Epic工作树: $epic_name"
  git worktree add "$epic_dir" "$branch_name"
  
  # 设置Epic配置
  setup_epic_config "$epic_dir" "$epic_name"
  
  ui_success "Epic工作树创建完成: $epic_dir"
}

create_temp_worktree() {
  local branch_name="$1"
  
  local temp_dir
  temp_dir="$(config_get "core.temp_dir")/$branch_name"
  
  if [[ -d "$temp_dir" ]]; then
    ui_error "临时工作树已存在: $temp_dir"
    return 1
  fi
  
  git worktree add "$temp_dir" "$branch_name"
  ui_success "临时工作树创建完成: $temp_dir"
}

cleanup_worktrees() {
  local cleanup_policy
  cleanup_policy=$(config_get "sync.cleanup_policy")
  
  local worktrees_to_clean
  worktrees_to_clean=($(find_cleanable_worktrees))
  
  if [[ ${#worktrees_to_clean[@]} -eq 0 ]]; then
    ui_info "没有需要清理的工作树"
    return
  fi
  
  case "$cleanup_policy" in
    "auto")
      clean_worktrees_auto "${worktrees_to_clean[@]}"
      ;;
    "ask")
      clean_worktrees_interactive "${worktrees_to_clean[@]}"
      ;;
    "keep")
      ui_info "配置为保留所有工作树"
      ;;
  esac
}

find_cleanable_worktrees() {
  # 查找已合并分支的工作树
  git worktree list --porcelain | \
  awk '/^worktree/ {path=$2} /^branch/ {branch=$2} /^$/ {print path":"branch}' | \
  while IFS=: read -r path branch; do
    if git merge-base --is-ancestor "$branch" "$(git_default_branch)"; then
      echo "$path"
    fi
  done
}

clean_worktrees_interactive() {
  local worktrees=("$@")
  
  ui_info "发现可清理的工作树："
  for i in "${!worktrees[@]}"; do
    echo "  $((i+1)). ${worktrees[i]}"
  done
  
  local choices
  choices=(
    "清理所有"
    "选择性清理"
    "查看磁盘占用"
    "取消"
  )
  
  local choice
  choice=$(ui_select "选择清理方式:" "${choices[@]}")
  
  case "$choice" in
    "清理所有")
      clean_worktrees_batch "${worktrees[@]}"
      ;;
    "选择性清理")
      clean_worktrees_selective "${worktrees[@]}"
      ;;
    "查看磁盘占用")
      show_worktree_disk_usage "${worktrees[@]}"
      clean_worktrees_interactive "${worktrees[@]}"  # 递归调用
      ;;
  esac
}
```

### 6. 冲突解决器 (conflict_resolver.sh)

**职责**: 冲突检测、解决策略、用户交互

```bash
# 冲突类型枚举
declare -r CONFLICT_FILE="file"
declare -r CONFLICT_CONTENT="content"
declare -r CONFLICT_RENAME="rename"
declare -r CONFLICT_DELETE="delete"

# 解决策略
declare -r RESOLVE_MANUAL="manual"
declare -r RESOLVE_OURS="ours"
declare -r RESOLVE_THEIRS="theirs"
declare -r RESOLVE_AUTO="auto"

detect_conflicts() {
  local source_branch="$1"
  local target_branch="$2"
  
  # 创建临时合并测试
  local temp_branch="temp-conflict-test-$$"
  git checkout -b "$temp_branch" "$target_branch" >/dev/null 2>&1
  
  local conflicts
  if ! git merge --no-commit --no-ff "$source_branch" >/dev/null 2>&1; then
    # 检测冲突文件
    conflicts=($(git diff --name-only --diff-filter=U))
    
    # 分析冲突类型
    for file in "${conflicts[@]}"; do
      analyze_conflict_type "$file"
    done
  fi
  
  # 清理临时分支
  git merge --abort >/dev/null 2>&1 || true
  git checkout - >/dev/null 2>&1
  git branch -D "$temp_branch" >/dev/null 2>&1
  
  echo "${conflicts[@]}"
}

resolve_conflicts_interactive() {
  local conflict_files=("$@")
  
  ui_warning "发现 ${#conflict_files[@]} 个冲突文件"
  
  for file in "${conflict_files[@]}"; do
    resolve_single_conflict "$file"
  done
}

resolve_single_conflict() {
  local file="$1"
  
  # 显示冲突信息
  show_conflict_preview "$file"
  
  local strategies
  strategies=(
    "手动编辑"
    "使用我的版本"
    "使用他们的版本"
    "自动合并"
    "跳过此文件"
  )
  
  local strategy
  strategy=$(ui_select "解决冲突: $file" "${strategies[@]}")
  
  case "$strategy" in
    "手动编辑")
      open_conflict_editor "$file"
      ;;
    "使用我的版本")
      git checkout --ours -- "$file"
      git add "$file"
      ;;
    "使用他们的版本")
      git checkout --theirs -- "$file"
      git add "$file"
      ;;
    "自动合并")
      auto_resolve_conflict "$file"
      ;;
    "跳过此文件")
      ui_info "跳过文件: $file"
      return
      ;;
  esac
  
  ui_success "冲突已解决: $file"
}

auto_resolve_conflict() {
  local file="$1"
  
  # 简单的自动合并策略
  # 1. 如果是纯新增行，保留所有
  # 2. 如果是配置文件，尝试智能合并
  # 3. 否则提示手动处理
  
  local conflict_type
  conflict_type=$(analyze_conflict_pattern "$file")
  
  case "$conflict_type" in
    "additive")
      # 纯新增冲突，保留双方
      resolve_additive_conflict "$file"
      ;;
    "config")
      # 配置文件，尝试智能合并
      resolve_config_conflict "$file"
      ;;
    *)
      ui_warning "无法自动解决，需要手动处理"
      open_conflict_editor "$file"
      ;;
  esac
}

show_conflict_preview() {
  local file="$1"
  
  ui_info "冲突预览: $file"
  
  # 显示冲突区域的上下文
  grep -n -B3 -A3 '^<<<<<<<\|^=======\|^>>>>>>>' "$file" | \
  head -20 | \
  while IFS=: read -r line_num content; do
    case "$content" in
      *'<<<<<<<'*)
        ui_error "  $line_num: $content"
        ;;
      *'======='*)
        ui_warning "  $line_num: $content"
        ;;
      *'>>>>>>>'*)
        ui_success "  $line_num: $content"
        ;;
      *)
        echo "  $line_num: $content"
        ;;
    esac
  done
}
```

### 7. 交互界面 (utils/ui.sh)

**职责**: 颜色输出、选择菜单、进度显示

```bash
# 颜色配置
setup_colors() {
  if [[ "$(config_get "ui.color")" == "auto" ]]; then
    if [[ -t 1 ]]; then
      USE_COLOR=true
    else
      USE_COLOR=false
    fi
  else
    USE_COLOR=$(config_get "ui.color")
  fi
  
  if [[ "$USE_COLOR" == "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    NC='\033[0m'
  else
    RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' BOLD='' NC=''
  fi
}

# 状态图标
declare -r ICON_SUCCESS="✔"
declare -r ICON_WARNING="⚠"
declare -r ICON_ERROR="✗"
declare -r ICON_INFO="ℹ"
declare -r ICON_PROGRESS="▶"

ui_select() {
  local question="$1"
  shift
  local options=("$@")
  
  echo -e "${CYAN}$question${NC}"
  
  for i in "${!options[@]}"; do
    echo "  $((i+1)). ${options[i]}"
  done
  
  local choice
  while true; do
    read -p "请选择 [1-${#options[@]}]: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && \
       [[ "$choice" -ge 1 ]] && \
       [[ "$choice" -le ${#options[@]} ]]; then
      echo "${options[$((choice-1))]}"
      return
    fi
    
    ui_error "无效选择，请输入 1-${#options[@]}"
  done
}

ui_progress() {
  local current="$1"
  local total="$2"
  local message="$3"
  
  local percentage=$((current * 100 / total))
  local bar_length=30
  local filled_length=$((percentage * bar_length / 100))
  
  printf "\r${CYAN}%s${NC} [" "$message"
  
  for ((i=0; i<filled_length; i++)); do
    printf "█"
  done
  
  for ((i=filled_length; i<bar_length; i++)); do
    printf "░"
  done
  
  printf "] %d%% (%d/%d)" "$percentage" "$current" "$total"
  
  if [[ "$current" -eq "$total" ]]; then
    echo
  fi
}

ui_tree() {
  local data="$1"
  
  # 解析依赖关系数据并生成ASCII树
  # 输入格式: "branch1:dep1,dep2 branch2:dep1"
  
  local -A branches deps
  
  while IFS=: read -r branch dep_list; do
    branches["$branch"]=1
    deps["$branch"]="$dep_list"
  done <<< "$data"
  
  # 找出根节点（没有依赖的分支）
  local roots=()
  for branch in "${!branches[@]}"; do
    if [[ -z "${deps[$branch]}" ]]; then
      roots+=("$branch")
    fi
  done
  
  # 递归绘制树
  for root in "${roots[@]}"; do
    draw_tree_node "$root" "" true
  done
}

draw_tree_node() {
  local node="$1"
  local prefix="$2"
  local is_last="$3"
  
  local node_icon
  node_icon=$(get_branch_icon "$node")
  
  if [[ "$is_last" == "true" ]]; then
    echo "${prefix}└─ $node_icon $node"
    local new_prefix="${prefix}   "
  else
    echo "${prefix}├─ $node_icon $node"
    local new_prefix="${prefix}│  "
  fi
  
  # 绘制子节点
  local children
  children=($(get_branch_children "$node"))
  
  for i in "${!children[@]}"; do
    local child="${children[i]}"
    local child_is_last=false
    
    if [[ $i -eq $((${#children[@]} - 1)) ]]; then
      child_is_last=true
    fi
    
    draw_tree_node "$child" "$new_prefix" "$child_is_last"
  done
}
```

## 数据流设计

### 命令执行流
```
用户输入 → 参数解析 → 环境检查 → 配置加载 
    ↓
命令路由 → 业务逻辑 → Git操作 → 状态更新 
    ↓
结果输出 → 清理资源 → 退出
```

### 状态管理流
```
Git状态 → 状态检查器 → 状态缓存 → 依赖计算
    ↓
状态变更 → 缓存失效 → 重新计算 → 通知UI
```

### 同步执行流
```
同步请求 → 计划生成 → 用户确认 → 执行操作
    ↓
冲突检测 → 冲突解决 → 状态更新 → 清理工作
```

## 错误处理架构

### 错误分类
1. **用户错误** (1xx): 参数错误、使用方式错误
2. **环境错误** (2xx): Git状态异常、文件权限问题
3. **业务错误** (3xx): 冲突、依赖循环
4. **系统错误** (4xx): 内部错误、意外异常

### 错误处理流程
```bash
错误发生 → 错误分类 → 上下文收集 → 用户友好提示
    ↓
修复建议 → 安全清理 → 日志记录 → 优雅退出
```

## 性能优化策略

### 缓存机制
- **状态缓存**: 分支状态信息缓存30秒
- **依赖缓存**: 依赖关系缓存直到Git状态变更
- **配置缓存**: 配置信息进程内缓存

### 批量操作
- **并行Git查询**: 使用后台进程并行获取分支信息
- **批量工作树操作**: 合并多个工作树切换操作
- **延迟计算**: 只在需要时计算复杂依赖关系

### 内存管理
- **流式处理**: 大量分支信息使用流式处理
- **及时清理**: 临时文件和变量及时释放
- **引用传递**: 大对象使用引用而非拷贝

## 扩展点设计

### Hook系统
- **pre-sync**: 同步前检查
- **post-sync**: 同步后清理
- **conflict-detect**: 自定义冲突检测
- **conflict-resolve**: 自定义冲突解决

### 插件接口
```bash
# 插件注册
register_command() {
  local name="$1"
  local handler="$2"
  CUSTOM_COMMANDS["$name"]="$handler"
}

# 插件Hook
run_plugin_hook() {
  local hook_name="$1"
  shift
  local args=("$@")
  
  for plugin in ~/.git-pr/plugins/*/hooks/"$hook_name"; do
    [[ -x "$plugin" ]] && "$plugin" "${args[@]}"
  done
}
```

这个架构设计提供了清晰的模块分离、可扩展的插件系统和健壮的错误处理机制。