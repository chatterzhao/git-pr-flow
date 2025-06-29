#!/usr/bin/env bash

# Git PR Flow - 项目级配置系统
# 管理 .gpf/ 目录下的项目级配置，替代分散的 YAML 文件

# 引入依赖
[[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ -f "$(dirname "${BASH_SOURCE[0]}")/context.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/context.sh"

# ============================================================================
# 配置文件路径定义
# ============================================================================

readonly GPF_CONFIG_DIR=".gpf"
readonly GPF_MAIN_CONFIG="$GPF_CONFIG_DIR/config.yaml"
readonly GPF_USER_PREFERENCES="$GPF_CONFIG_DIR/user-preferences.yaml"
readonly GPF_EPICS_INDEX="$GPF_CONFIG_DIR/epics.yaml"
readonly GPF_CONFIG_VERSION="1.0"

# ============================================================================
# 项目配置文件操作
# ============================================================================

# 检查 .gpf 目录是否存在
gpf_config_dir_exists() {
    [[ -d "$GPF_CONFIG_DIR" ]]
}

# 检查项目配置是否存在
gpf_project_config_exists() {
    [[ -f "$GPF_MAIN_CONFIG" ]]
}

# 创建 .gpf 目录结构
create_gpf_directory() {
    if [[ ! -d "$GPF_CONFIG_DIR" ]]; then
        mkdir -p "$GPF_CONFIG_DIR"
        echo "✅ 创建 .gpf 配置目录"
    fi
}

# 创建项目主配置文件
create_project_config() {
    local base_branch="${1:-$(detect_base_branch "project")}"
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "❌ 错误: 不在 Git 仓库中"
        return 1
    }
    
    local project_name
    project_name=$(basename "$project_root")
    
    create_gpf_directory
    
    cat > "$GPF_MAIN_CONFIG" << EOF
# Git PR Flow 项目配置文件
# 项目: $project_name
# 创建于: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

project:
  name: "$project_name"
  base_branch: "$base_branch"
  root_path: "$(pwd)"
  
config:
  version: "$GPF_CONFIG_VERSION"
  created_at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  last_updated: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# 工作流设置
workflow:
  type: "gitflow"
  epic_naming: "epic/{name}"
  feature_naming: "{epic}/{feature}"
  worktree_dir: ".worktrees"
  
# 默认策略  
defaults:
  pr_strategy:
    epic_to_base: "progressive"
    feature_to_epic: "feature_to_epic"
  auto_cleanup: false
  auto_sync: false
  auto_switch_branch: true

# 集成设置
integrations:
  github: 
    enabled: false
    auto_pr_description: true
  vs_code:
    enabled: true
    auto_workspace: true
EOF

    echo "✅ 创建项目配置: $GPF_MAIN_CONFIG"
}

# 创建用户偏好配置文件
create_user_preferences() {
    create_gpf_directory
    
    cat > "$GPF_USER_PREFERENCES" << EOF
# Git PR Flow 用户偏好配置
# 这些设置会覆盖项目默认配置

user:
  name: "$(git config user.name 2>/dev/null || echo 'Unknown')"
  email: "$(git config user.email 2>/dev/null || echo 'unknown@example.com')"

# 个人偏好
preferences:
  auto_switch_branch: true
  auto_sync: false
  auto_cleanup: false
  show_progress: true
  color_output: true

# 编辑器和工具
tools:
  editor: "\${EDITOR:-code}"
  diff_tool: "\${DIFF_TOOL:-code --diff}"
  merge_tool: "\${MERGE_TOOL:-code --merge}"

# 通知设置
notifications:
  pr_created: true
  conflicts_detected: true
  epic_completed: true
EOF

    echo "✅ 创建用户偏好配置: $GPF_USER_PREFERENCES"
}

# 创建 Epic 索引文件
create_epics_index() {
    create_gpf_directory
    
    cat > "$GPF_EPICS_INDEX" << EOF
# Git PR Flow Epic 索引
# 记录项目中的所有 Epic 信息

epics: []

# 索引元数据
index:
  created_at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  last_updated: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  total_count: 0
EOF

    echo "✅ 创建 Epic 索引: $GPF_EPICS_INDEX"
}

# 初始化完整的项目配置
init_project_config() {
    local base_branch="$1"
    
    if gpf_project_config_exists; then
        echo "ℹ️  项目配置已存在，跳过创建"
        return 0
    fi
    
    echo "🔧 初始化 Git PR Flow 项目配置..."
    
    create_project_config "$base_branch"
    create_user_preferences
    create_epics_index
    
    echo "🎉 项目配置初始化完成!"
    echo "   配置目录: $GPF_CONFIG_DIR"
    echo "   主配置: $GPF_MAIN_CONFIG"
    echo "   用户偏好: $GPF_USER_PREFERENCES"
    echo "   Epic索引: $GPF_EPICS_INDEX"
}

# ============================================================================
# 配置读取函数
# ============================================================================

# 读取项目配置字段
read_project_config() {
    local key="$1"
    local default="$2"
    
    if [[ ! -f "$GPF_MAIN_CONFIG" ]]; then
        echo "$default"
        return 1
    fi
    
    # 简单的 YAML 解析
    local value
    value=$(grep -E "^[[:space:]]*${key}:" "$GPF_MAIN_CONFIG" | head -1 | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# 读取用户偏好配置
read_user_preference() {
    local key="$1"
    local default="$2"
    
    if [[ ! -f "$GPF_USER_PREFERENCES" ]]; then
        echo "$default"
        return 1
    fi
    
    local value
    value=$(grep -E "^[[:space:]]*${key}:" "$GPF_USER_PREFERENCES" | head -1 | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# 获取项目基础分支
get_project_base_branch() {
    read_project_config "base_branch" "develop"
}

# 获取工作流类型
get_workflow_type() {
    read_project_config "type" "gitflow"
}

# 获取 worktree 目录
get_worktree_dir() {
    read_project_config "worktree_dir" ".worktrees"
}

# ============================================================================
# 配置写入函数
# ============================================================================

# 更新项目配置字段
update_project_config() {
    local key="$1"
    local value="$2"
    
    if [[ ! -f "$GPF_MAIN_CONFIG" ]]; then
        echo "❌ 项目配置文件不存在: $GPF_MAIN_CONFIG"
        return 1
    fi
    
    # 创建临时文件
    local temp_file="/tmp/gpf-config-$$"
    
    if grep -q "^[[:space:]]*${key}:" "$GPF_MAIN_CONFIG"; then
        # 更新现有键
        sed "s/^[[:space:]]*${key}:.*/${key}: \"${value}\"/" "$GPF_MAIN_CONFIG" > "$temp_file"
    else
        # 添加新键到相应部分
        cp "$GPF_MAIN_CONFIG" "$temp_file"
        echo "${key}: \"${value}\"" >> "$temp_file"
    fi
    
    # 更新 last_updated 时间戳
    sed -i.bak "s/last_updated:.*/last_updated: \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"/" "$temp_file"
    
    # 原子性替换
    mv "$temp_file" "$GPF_MAIN_CONFIG"
    rm -f "${GPF_MAIN_CONFIG}.bak"
    
    echo "✅ 更新项目配置: $key = $value"
}

# 更新用户偏好
update_user_preference() {
    local key="$1"
    local value="$2"
    
    if [[ ! -f "$GPF_USER_PREFERENCES" ]]; then
        create_user_preferences
    fi
    
    local temp_file="/tmp/gpf-prefs-$$"
    
    if grep -q "^[[:space:]]*${key}:" "$GPF_USER_PREFERENCES"; then
        sed "s/^[[:space:]]*${key}:.*/${key}: ${value}/" "$GPF_USER_PREFERENCES" > "$temp_file"
    else
        cp "$GPF_USER_PREFERENCES" "$temp_file"
        echo "${key}: ${value}" >> "$temp_file"
    fi
    
    mv "$temp_file" "$GPF_USER_PREFERENCES"
    echo "✅ 更新用户偏好: $key = $value"
}

# ============================================================================
# Epic 索引管理
# ============================================================================

# 添加 Epic 到索引
add_epic_to_index() {
    local epic_name="$1"
    local description="$2"
    local base_branch="$3"
    
    if [[ ! -f "$GPF_EPICS_INDEX" ]]; then
        create_epics_index
    fi
    
    # 检查 Epic 是否已存在
    if grep -q "name: \"$epic_name\"" "$GPF_EPICS_INDEX"; then
        echo "ℹ️  Epic '$epic_name' 已在索引中"
        return 0
    fi
    
    # 创建临时文件
    local temp_file="/tmp/gpf-epics-$$"
    
    # 在 epics: [] 行后添加新的 Epic 条目
    local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    awk -v epic_name="$epic_name" -v description="$description" -v base_branch="$base_branch" -v current_time="$current_time" '
    /^epics: \[\]$/ {
        print "epics:"
        print "  - name: \"" epic_name "\""
        print "    description: \"" description "\""
        print "    base_branch: \"" base_branch "\""
        print "    epic_branch: \"epic/" epic_name "\""
        print "    created_at: \"" current_time "\""
        print "    status: \"active\""
        next
    }
    /^epics:$/ && getline ~ /^  - / {
        print $0
        print "  - name: \"" epic_name "\""
        print "    description: \"" description "\""
        print "    base_branch: \"" base_branch "\""
        print "    epic_branch: \"epic/" epic_name "\""
        print "    created_at: \"" current_time "\""
        print "    status: \"active\""
        print $0
        next
    }
    { print }
    ' "$GPF_EPICS_INDEX" > "$temp_file"
    
    # 更新时间戳和计数
    sed -i.bak "s/last_updated:.*/last_updated: \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"/" "$temp_file"
    
    # 计算 Epic 数量并更新
    local epic_count
    epic_count=$(grep -c "name: \"" "$temp_file")
    sed -i.bak "s/total_count:.*/total_count: $epic_count/" "$temp_file"
    
    mv "$temp_file" "$GPF_EPICS_INDEX"
    rm -f "${GPF_EPICS_INDEX}.bak"
    
    echo "✅ 添加 Epic 到索引: $epic_name"
}

# 移除 Epic 从索引
remove_epic_from_index() {
    local epic_name="$1"
    
    if [[ ! -f "$GPF_EPICS_INDEX" ]]; then
        echo "ℹ️  Epic 索引不存在"
        return 0
    fi
    
    local temp_file="/tmp/gpf-epics-$$"
    
    # 移除指定的 Epic 条目
    awk -v epic_name="$epic_name" '
    /^  - name: "/ {
        if ($0 ~ "\"" epic_name "\"") {
            # 跳过这个 Epic 的所有行
            while (getline && $0 ~ /^    /) { }
            if ($0 !~ /^  - name:/ && $0 !~ /^$/ && $0 !~ /^#/) {
                print
            }
            next
        }
    }
    { print }
    ' "$GPF_EPICS_INDEX" > "$temp_file"
    
    # 更新时间戳和计数
    sed -i.bak "s/last_updated:.*/last_updated: \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"/" "$temp_file"
    
    local epic_count
    epic_count=$(grep -c "name: \"" "$temp_file")
    sed -i.bak "s/total_count:.*/total_count: $epic_count/" "$temp_file"
    
    mv "$temp_file" "$GPF_EPICS_INDEX"
    rm -f "${GPF_EPICS_INDEX}.bak"
    
    echo "✅ 从索引中移除 Epic: $epic_name"
}

# 列出所有 Epic
list_epics() {
    if [[ ! -f "$GPF_EPICS_INDEX" ]]; then
        echo "ℹ️  没有找到 Epic 索引"
        return 0
    fi
    
    echo "📋 项目 Epic 列表:"
    echo
    
    grep -A 5 "name: \"" "$GPF_EPICS_INDEX" | while IFS= read -r line; do
        if [[ "$line" =~ name:\ \"(.*)\" ]]; then
            local epic_name="${BASH_REMATCH[1]}"
            echo "🎯 Epic: $epic_name"
            
            # 读取描述
            read -r desc_line
            if [[ "$desc_line" =~ description:\ \"(.*)\" ]]; then
                echo "   描述: ${BASH_REMATCH[1]}"
            fi
            
            # 读取基础分支
            read -r base_line
            if [[ "$base_line" =~ base_branch:\ \"(.*)\" ]]; then
                echo "   基础分支: ${BASH_REMATCH[1]}"
            fi
            
            # 读取状态
            read -r epic_line; read -r created_line; read -r status_line
            if [[ "$status_line" =~ status:\ \"(.*)\" ]]; then
                echo "   状态: ${BASH_REMATCH[1]}"
            fi
            
            echo
        fi
    done
}

# ============================================================================
# 配置迁移工具
# ============================================================================

# 从现有 YAML 文件迁移配置
migrate_from_yaml() {
    local yaml_file="$1"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "⚠️  YAML 文件不存在: $yaml_file"
        return 1
    fi
    
    echo "🔄 从 YAML 迁移配置: $yaml_file"
    
    # 读取关键字段
    local epic_name base_branch description
    epic_name=$(grep "^epic_name:" "$yaml_file" | cut -d: -f2 | tr -d ' "'"'"'' | head -1)
    base_branch=$(grep "^base_branch:" "$yaml_file" | cut -d: -f2 | tr -d ' "'"'"'' | head -1)
    description=$(grep "^description:" "$yaml_file" | cut -d: -f2 | sed 's/^[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | head -1)
    
    if [[ -n "$epic_name" ]]; then
        echo "  迁移 Epic: $epic_name"
        add_epic_to_index "$epic_name" "$description" "$base_branch"
    fi
    
    # 备份原文件
    local backup_dir=".gpf/yaml-backup"
    mkdir -p "$backup_dir"
    cp "$yaml_file" "$backup_dir/$(basename "$yaml_file").$(date +%Y%m%d_%H%M%S)"
    
    echo "  ✅ 迁移完成，原文件已备份到 $backup_dir"
}

# 批量迁移工作树中的 YAML 文件
migrate_all_yaml_configs() {
    echo "🔄 开始批量迁移 YAML 配置文件..."
    
    local yaml_files
    yaml_files=$(find .worktrees -name ".git-pr-flow.yaml" 2>/dev/null)
    
    if [[ -z "$yaml_files" ]]; then
        echo "ℹ️  没有找到需要迁移的 YAML 配置文件"
        return 0
    fi
    
    local count=0
    while IFS= read -r yaml_file; do
        migrate_from_yaml "$yaml_file"
        ((count++))
    done <<< "$yaml_files"
    
    echo "🎉 迁移完成，共处理 $count 个 YAML 配置文件"
}

# ============================================================================
# 工具和调试函数
# ============================================================================

# 显示项目配置概览
show_project_config() {
    echo "📊 Git PR Flow 项目配置概览"
    echo "================================"
    echo
    
    if ! gpf_project_config_exists; then
        echo "❌ 项目配置未初始化"
        echo "   运行 'gpf init' 来初始化配置"
        return 1
    fi
    
    echo "📁 配置目录: $GPF_CONFIG_DIR"
    echo "📝 主配置文件: $GPF_MAIN_CONFIG"
    echo
    
    echo "🎯 项目信息:"
    echo "   名称: $(read_project_config "name" "N/A")"
    echo "   基础分支: $(read_project_config "base_branch" "N/A")"
    echo "   工作流类型: $(read_project_config "type" "N/A")"
    echo "   Worktree目录: $(read_project_config "worktree_dir" "N/A")"
    echo
    
    echo "👤 用户偏好:"
    echo "   自动切换分支: $(read_user_preference "auto_switch_branch" "N/A")"
    echo "   自动同步: $(read_user_preference "auto_sync" "N/A")"
    echo "   自动清理: $(read_user_preference "auto_cleanup" "N/A")"
    echo
    
    list_epics
}

# 验证配置文件完整性
validate_project_config() {
    echo "🔍 验证项目配置..."
    
    local errors=0
    
    # 检查必需文件
    if [[ ! -f "$GPF_MAIN_CONFIG" ]]; then
        echo "❌ 缺少主配置文件: $GPF_MAIN_CONFIG"
        ((errors++))
    fi
    
    # 检查配置版本
    if [[ -f "$GPF_MAIN_CONFIG" ]]; then
        local config_version
        config_version=$(read_project_config "version" "")
        if [[ "$config_version" != "$GPF_CONFIG_VERSION" ]]; then
            echo "⚠️  配置版本不匹配: $config_version (期望: $GPF_CONFIG_VERSION)"
        fi
    fi
    
    # 检查基础分支是否存在
    local base_branch
    base_branch=$(get_project_base_branch)
    if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
        echo "⚠️  基础分支不存在: $base_branch"
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ 配置验证通过"
    else
        echo "❌ 发现 $errors 个配置错误"
        return 1
    fi
}