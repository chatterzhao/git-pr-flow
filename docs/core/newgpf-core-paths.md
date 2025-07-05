# NewGPF 核心公共组件设计 - 路径管理

> 📖 **相关文档**: [主文档](../../newgpf-README.md) | [架构设计](../newgpf-ARCHITECTURE.md) | [命令详细](../newgpf-COMMANDS.md) | [术语表](../newgpf-术语表.md) | [核心组件索引](../newgpf-CORE-COMPONENTS.md)

## 设计原则

基于用户的架构哲学："基本方法在 core 文档，并且多个命令是一样的方法，也在core里将多个基本方法组装为高级一点的方法。command文档根据具体命令调用通用或某个命令不一样的调用core 方法扩展加一些自有方法组装为该命令所需方法"

1. **单一职责**：每个组件只负责一个明确的功能域
2. **无副作用**：纯函数设计，输入确定输出确定
3. **错误透明**：清晰的错误传播和处理机制
4. **测试友好**：每个函数都可以独立测试
5. **平台兼容**：跨平台文件系统和路径处理
6. **职责分离**：core提供基础工具，command组合使用
7. **🆕 GitHub集成**：统一的GitHub CLI检查和PR状态管理

---

## 2. paths.sh - 路径管理

### 核心功能
统一的路径计算和转换，处理所有与文件系统路径相关的操作。

### 🎯 精细化的后缀检测和处理（基础方法）

```bash
# 提取输入中的后缀标识符（原子方法）
# 原：extract_suffix() + path_extract_suffix() → 新：path_extract_suffix()
path_extract_suffix() {
    local input="$1"
    
    if [[ "$input" =~ -e$ ]]; then
        echo "e"
    elif [[ "$input" =~ -ef$ ]]; then
        echo "ef"  
    else
        echo "none"
    fi
}

# 清除输入中的后缀标识符（基础原子方法）
strip_suffix_from_input() {
    local input="$1"
    local suffix
    suffix=$(path_extract_suffix "$input")
    
    case "$suffix" in
        "e")
            echo "${input%-e}"
            ;;
        "ef")
            echo "${input%-ef}"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# 验证输入后缀与期望类型匹配（验证层方法）
validate_input_suffix_matches_expected() {
    local input="$1"
    local expected_suffix="$2"  # "e" 或 "ef"
    
    local current_suffix
    current_suffix=$(path_extract_suffix "$input")
    
    case "$current_suffix" in
        "none")
            # 没有后缀，符合期望（可以自动补全）
            return 0
            ;;
        "$expected_suffix")
            # 后缀匹配期望
            return 0
            ;;
        *)
            # 后缀不匹配期望
            echo "错误：输入后缀 -$current_suffix 与期望后缀 -$expected_suffix 不匹配" >&2
            return 1
            ;;
    esac
}

# 为输入补全缺失的后缀标识符（处理层方法）
ensure_suffix_present() {
    local input="$1"
    local required_suffix="$2"  # "e" 或 "ef"
    
    local current_suffix
    current_suffix=$(path_extract_suffix "$input")
    
    if [[ "$current_suffix" == "none" ]]; then
        # 没有后缀，添加所需后缀
        echo "$input-$required_suffix"
    else
        # 已有后缀，直接返回（假设已通过验证）
        echo "$input"
    fi
}

# 强制替换输入的后缀标识符（处理层方法）
replace_suffix_forcefully() {
    local input="$1"
    local required_suffix="$2"  # "e" 或 "ef"
    
    local clean_name
    clean_name=$(strip_suffix_from_input "$input")
    echo "$clean_name-$required_suffix"
}
```

### 🎯 精细化的前缀检测和处理（基础方法）

```bash
# 提取输入中的前缀标识符（基础原子方法）
extract_prefix_from_input() {
    local input="$1"
    
    if [[ "$input" =~ ^epic-(.+)$ ]]; then
        echo "epic-"
    elif [[ "$input" =~ ^epic_(.+)$ ]]; then
        echo "epic_"
    elif [[ "$input" =~ ^epic/(.+)$ ]]; then
        echo "epic/"
    else
        echo "none"
    fi
}

# 清除输入中的epic前缀（基础原子方法）
strip_epic_prefix_from_input() {
    local input="$1"
    local prefix
    prefix=$(extract_prefix_from_input "$input")
    
    case "$prefix" in
        "epic-")
            echo "${input#epic-}"
            ;;
        "epic_")
            echo "${input#epic_}"
            ;;
        "epic/")
            echo "${input#epic/}"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# 验证epic前缀格式合法性（验证层方法）
validate_epic_prefix_format() {
    local input="$1"
    local prefix
    prefix=$(extract_prefix_from_input "$input")
    
    case "$prefix" in
        "none"|"epic-")
            # 没有前缀或标准前缀，都是合法的
            return 0
            ;;
        "epic_"|"epic/")
            # 非标准前缀，给出警告但不阻断
            echo "警告：建议使用标准前缀 epic- 而不是 $prefix" >&2
            return 0
            ;;
        *)
            # 其他情况
            return 1
            ;;
    esac
}

# 添加标准前缀（如果没有的话）（处理方法）
add_epic_prefix_if_missing() {
    local input="$1"
    local prefix
    prefix=$(extract_prefix_from_input "$input")
    
    if [[ "$prefix" == "none" ]]; then
        echo "epic-$input"
    else
        # 有前缀，先移除再添加标准前缀（避免重复）
        local clean_name
        clean_name=$(strip_epic_prefix_from_input "$input")
        echo "epic-$clean_name"
    fi
}

# 强制设置标准前缀（替换现有前缀）（处理方法）
force_set_epic_prefix() {
    local input="$1"
    local clean_name
    clean_name=$(strip_epic_prefix_from_input "$input")
    echo "epic-$clean_name"
}
```

### 🎯 通用高级组合方法（多命令共用）

```bash
# 将用户输入转化为标准epic分支名（处理层组合）
transform_input_to_epic_branch() {
    local user_input="$1"
    
    # 1. 验证前缀
    validate_epic_prefix_format "$user_input" || return 1
    
    # 2. 提取纯净名称
    local clean_name
    clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$user_input")")
    
    # 3. 验证名称合法性
    validate_name_format "$clean_name" || return 1
    
    # 4. 生成最终规范名称
    echo "epic-$clean_name-e"
}

# 将用户输入转化为标准feature分支名（处理层组合）
transform_input_to_feature_branch() {
    local feature_input="$1"
    local epic_input="$2"
    
    # 1. 处理Epic和Feature名称
    local clean_epic
    clean_epic=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$epic_input")")
    
    local clean_feature
    clean_feature=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$feature_input")")
    
    # 2. 验证名称合法性
    validate_name_format "$clean_feature" || return 1
    
    # 3. 智能构建Feature名称
    if [[ "$clean_feature" == "$clean_epic-"* ]]; then
        # Feature已包含Epic前缀：auth-login
        echo "epic-$clean_epic-e-$clean_feature-ef"
    else
        # Feature不包含Epic前缀：login
        echo "epic-$clean_epic-e-$clean_feature-ef"
    fi
}

# 全面验证并处理用户输入（多命令共用组合）
process_and_validate_user_input() {
    local user_input="$1"
    local expected_suffix="$2"      # "e" | "ef"
    local current_environment="${3:-}"  # 当前环境（可选）
    
    # 1. 基础验证
    validate_epic_prefix_format "$user_input" || return 1
    validate_input_suffix_matches_expected "$user_input" "$expected_suffix" || return 1
    
    # 2. 环境验证（如果提供）
    if [[ -n "$current_environment" ]]; then
        validate_input_environment_match "$user_input" "$current_environment" || return 1
    fi
    
    # 3. 处理并返回规范名称
    local clean_name
    clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$user_input")")
    echo "epic-$clean_name-$expected_suffix"
}

# 环境验证：检查用户输入是否与当前环境匹配（多命令共用）
validate_input_environment_match() {
    local user_input="$1"
    local current_environment="$2"  # "epic" | "feature" | "root"
    
    local input_suffix
    input_suffix=$(path_extract_suffix "$user_input")
    
    # 如果用户没有输入后缀，则不需要验证（可以自动补全）
    if [[ "$input_suffix" == "none" ]]; then
        return 0
    fi
    
    # 验证输入后缀与环境是否匹配
    case "$current_environment" in
        "epic")
            if [[ "$input_suffix" != "e" ]]; then
                echo "❌ 错误：在Epic环境中，但输入了 -$input_suffix 后缀" >&2
                echo "💡 建议：在Epic环境中应使用 -e 后缀或省略后缀" >&2
                return 1
            fi
            ;;
        "feature")
            if [[ "$input_suffix" != "ef" ]]; then
                echo "❌ 错误：在Feature环境中，但输入了 -$input_suffix 后缀" >&2
                echo "💡 建议：在Feature环境中应使用 -ef 后缀或省略后缀" >&2
                return 1
            fi
            ;;
        "root")
            # 在根目录环境中，不强制要求特定后缀
            return 0
            ;;
        *)
            echo "❌ 错误：未知的环境: $current_environment" >&2
            return 1
            ;;
    esac
    
    return 0
}
```

### 辅助工具方法（多命令共用）

```bash
# 名称格式验证（通用验证）
validate_name_format() {
    local name="$1"
    
    # 长度检查
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        echo "❌ 错误：名称长度必须在2-50字符之间" >&2
        return 1
    fi
    
    # 格式检查：允许小写字母、数字、连字符、下划线
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "❌ 错误：名称只能包含小写字母、数字、连字符、下划线" >&2
        return 1
    fi
    
    # 不能以连字符或下划线开头或结尾
    if [[ "$name" =~ ^[-_] ]] || [[ "$name" =~ [-_]$ ]]; then
        echo "❌ 错误：名称不能以连字符或下划线开头或结尾" >&2
        return 1
    fi
    
    return 0
}

# 从分支名提取Epic名称（通用工具）
extract_epic_from_branch() {
    local branch_name="$1"
    
    local suffix
    suffix=$(path_extract_suffix "$branch_name")
    
    case "$suffix" in
        "e")
            # Epic分支：epic-auth-e -> auth
            strip_suffix_from_input "$(strip_epic_prefix_from_input "$branch_name")"
            ;;
        "ef")
            # Feature分支：epic-auth-e-login-ef -> auth
            local clean_name
            clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$branch_name")")
            echo "${clean_name%-*}"  # 移除最后一个-及之后的内容
            ;;
        *)
            echo "❌ 错误：无法从分支名提取Epic: $branch_name" >&2
            return 1
            ;;
    esac
}
```