#!/usr/bin/env bash

# Git PR Flow - 配置管理工具
# 处理配置文件读写、Epic配置管理等

# 配置文件路径
readonly EPIC_CONFIG_FILE=".git-pr-flow.yaml"
readonly PROJECT_CONFIG_FILE=".git/pr-config"
readonly GLOBAL_CONFIG_FILE="$HOME/.gitprconfig"

# 检查Epic配置文件是否存在
config_epic_exists() {
    [[ -f "$EPIC_CONFIG_FILE" ]]
}

# 读取Epic配置
config_epic_get() {
    local key="$1"
    
    if ! config_epic_exists; then
        return 1
    fi
    
    # 简单的YAML解析（仅支持基本的 key: value 格式）
    grep "^$key:" "$EPIC_CONFIG_FILE" | sed "s/^$key:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
}

# 写入Epic配置
config_epic_set() {
    local key="$1"
    local value="$2"
    
    # 创建临时文件
    local temp_file="/tmp/git-pr-flow-config-$$"
    
    if config_epic_exists; then
        # 更新现有配置
        if grep -q "^$key:" "$EPIC_CONFIG_FILE"; then
            # 更新现有键
            sed "s/^$key:.*/$key: \"$value\"/" "$EPIC_CONFIG_FILE" > "$temp_file"
        else
            # 添加新键
            cp "$EPIC_CONFIG_FILE" "$temp_file"
            echo "$key: \"$value\"" >> "$temp_file"
        fi
    else
        # 创建新配置文件
        cat > "$temp_file" << EOF
# Git PR Flow Epic配置文件
# 自动生成于 $(current_iso_timestamp)

$key: "$value"
EOF
    fi
    
    # 原子性替换配置文件
    mv "$temp_file" "$EPIC_CONFIG_FILE"
    log_debug "设置Epic配置: $key = $value"
}

# 创建Epic配置文件
config_epic_create() {
    local epic_name="$1"
    local description="$2"
    local base_branch="$3"
    local worktree_path="$4"
    
    cat > "$EPIC_CONFIG_FILE" << EOF
# Git PR Flow Epic配置文件
# Epic: $epic_name
# 创建于: $(current_iso_timestamp)

epic_name: "$epic_name"
description: "$description"
base_branch: "$base_branch"
worktree_path: "$worktree_path"
config_version: "1.0"
created_at: "$(current_iso_timestamp)"
last_updated: "$(current_iso_timestamp)"

# 自动化设置
auto_switch_branch: true
auto_sync: false
auto_cleanup: false

# 工作流设置
workflow_type: "gitflow"
pr_strategy: "progressive"
EOF
    
    ui_success "创建Epic配置文件: $EPIC_CONFIG_FILE"
}

# 更新Epic配置的最后修改时间
config_epic_touch() {
    if config_epic_exists; then
        config_epic_set "last_updated" "$(current_iso_timestamp)"
    fi
}

# 验证Epic配置文件
config_epic_validate() {
    if ! config_epic_exists; then
        ui_error "Epic配置文件不存在: $EPIC_CONFIG_FILE"
        return 1
    fi
    
    local required_keys=("epic_name" "description" "base_branch" "config_version")
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if [[ -z "$(config_epic_get "$key")" ]]; then
            missing_keys+=("$key")
        fi
    done
    
    if [[ ${#missing_keys[@]} -gt 0 ]]; then
        ui_error "Epic配置文件缺少必要字段: ${missing_keys[*]}"
        return 1
    fi
    
    # 检查配置版本
    local config_version
    config_version=$(config_epic_get "config_version")
    if [[ "$config_version" != "1.0" ]]; then
        ui_warning "Epic配置文件版本不匹配: $config_version (期望: 1.0)"
    fi
    
    return 0
}

# 显示Epic配置信息
config_epic_show() {
    if ! config_epic_exists; then
        ui_error "Epic配置文件不存在"
        return 1
    fi
    
    if ! config_epic_validate; then
        return 1
    fi
    
    local epic_name description base_branch worktree_path created_at
    epic_name=$(config_epic_get "epic_name")
    description=$(config_epic_get "description")
    base_branch=$(config_epic_get "base_branch")
    worktree_path=$(config_epic_get "worktree_path")
    created_at=$(config_epic_get "created_at")
    
    ui_subheader "Epic配置信息"
    echo "  Epic名称: $epic_name"
    echo "  描述: $description"
    echo "  基础分支: $base_branch"
    echo "  工作树路径: $worktree_path"
    echo "  创建时间: $created_at"
    echo
}

# 项目配置管理（Git config格式）

# 读取项目配置
config_project_get() {
    local key="$1"
    local default="$2"
    
    local value
    if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        value=$(git config -f "$PROJECT_CONFIG_FILE" "$key" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# 设置项目配置
config_project_set() {
    local key="$1"
    local value="$2"
    
    # 确保配置文件目录存在
    ensure_dir "$(dirname "$PROJECT_CONFIG_FILE")"
    
    git config -f "$PROJECT_CONFIG_FILE" "$key" "$value"
    log_debug "设置项目配置: $key = $value"
}

# 删除项目配置
config_project_unset() {
    local key="$1"
    
    if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        git config -f "$PROJECT_CONFIG_FILE" --unset "$key" 2>/dev/null || true
        log_debug "删除项目配置: $key"
    fi
}

# 全局配置管理

# 读取全局配置
config_global_get() {
    local key="$1"
    local default="$2"
    
    local value
    if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
        value=$(git config -f "$GLOBAL_CONFIG_FILE" "$key" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# 设置全局配置
config_global_set() {
    local key="$1"
    local value="$2"
    
    # 确保配置文件目录存在
    ensure_dir "$(dirname "$GLOBAL_CONFIG_FILE")"
    
    git config -f "$GLOBAL_CONFIG_FILE" "$key" "$value"
    log_debug "设置全局配置: $key = $value"
}

# 配置查找层次（Epic -> 项目 -> 全局）
config_get() {
    local key="$1"
    local default="$2"
    
    # 1. 尝试从Epic配置读取
    local value
    if config_epic_exists; then
        value=$(config_epic_get "$key")
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    # 2. 尝试从项目配置读取
    value=$(config_project_get "$key")
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # 3. 尝试从全局配置读取
    value=$(config_global_get "$key")
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # 4. 返回默认值
    echo "$default"
}

# 智能配置设置（根据范围自动选择配置文件）
config_set() {
    local key="$1"
    local value="$2"
    local scope="${3:-auto}"
    
    case "$scope" in
        "epic")
            config_epic_set "$key" "$value"
            ;;
        "project")
            config_project_set "$key" "$value"
            ;;
        "global")
            config_global_set "$key" "$value"
            ;;
        "auto")
            # 自动选择：如果在Epic环境中，使用Epic配置，否则使用项目配置
            if config_epic_exists; then
                config_epic_set "$key" "$value"
            else
                config_project_set "$key" "$value"
            fi
            ;;
        *)
            ui_error "无效的配置范围: $scope"
            return 1
            ;;
    esac
}

# 列出所有配置
config_list() {
    local scope="${1:-all}"
    
    case "$scope" in
        "epic")
            if config_epic_exists; then
                ui_subheader "Epic配置 ($EPIC_CONFIG_FILE)"
                cat "$EPIC_CONFIG_FILE"
            else
                ui_info "没有Epic配置文件"
            fi
            ;;
        "project")
            if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
                ui_subheader "项目配置 ($PROJECT_CONFIG_FILE)"
                git config -f "$PROJECT_CONFIG_FILE" --list
            else
                ui_info "没有项目配置文件"
            fi
            ;;
        "global")
            if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
                ui_subheader "全局配置 ($GLOBAL_CONFIG_FILE)"
                git config -f "$GLOBAL_CONFIG_FILE" --list
            else
                ui_info "没有全局配置文件"
            fi
            ;;
        "all")
            config_list "epic"
            echo
            config_list "project"
            echo
            config_list "global"
            ;;
        *)
            ui_error "无效的配置范围: $scope"
            return 1
            ;;
    esac
}

# 配置文件备份和恢复
config_backup() {
    local backup_dir=".git/pr-flow-backup"
    ensure_dir "$backup_dir"
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    
    if config_epic_exists; then
        cp "$EPIC_CONFIG_FILE" "$backup_dir/epic_config_$timestamp.yaml"
        ui_success "备份Epic配置: $backup_dir/epic_config_$timestamp.yaml"
    fi
    
    if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        cp "$PROJECT_CONFIG_FILE" "$backup_dir/project_config_$timestamp"
        ui_success "备份项目配置: $backup_dir/project_config_$timestamp"
    fi
}

# 获取默认配置值
config_defaults() {
    cat << EOF
# Git PR Flow 默认配置
core.epic_dir=.worktrees
core.temp_dir=.worktrees
sync.default_scope=deps
sync.conflict_mode=prompt
sync.auto_cleanup=false
worktree.auto_cleanup=true
worktree.disk_threshold=1GB
pr.auto_description=true
pr.include_epic_context=true
ui.show_progress=true
ui.color=auto
EOF
}