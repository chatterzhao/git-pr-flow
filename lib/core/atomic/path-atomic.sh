#!/bin/bash
# NewGPF Core - Path Processing Atomic Methods
# 路径处理原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 提取输入中的后缀标识符
# 参数：(input_string)
# 返回：e|ef|none
path_extract_suffix() {
    local input="$1"
    
    if [[ "$input" =~ -ef$ ]]; then
        echo "ef"
    elif [[ "$input" =~ -e$ ]]; then
        echo "e"
    else
        echo "none"
    fi
}

# 清除输入中的后缀标识符
# 参数：(input_string)
# 返回：清理后的字符串
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

# 提取输入中的前缀标识符
# 参数：(input_string)
# 返回：epic-|epic_|epic/|none
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

# 清除输入中的epic前缀
# 参数：(input_string)
# 返回：清理后的字符串
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

# 验证名称格式
# 参数：(name)
# 返回：0（有效）或1（无效），错误信息输出到stderr
validate_name_format() {
    local name="$1"
    
    # 长度检查
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        echo "❌ 错误：名称长度必须在2-50字符之间，当前长度：${#name}" >&2
        return 1
    fi
    
    # 格式检查：允许小写字母、数字、连字符、下划线
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "❌ 错误：名称只能包含小写字母、数字、连字符、下划线，当前：$name" >&2
        return 1
    fi
    
    # 不能以连字符或下划线开头或结尾
    if [[ "$name" =~ ^[-_] ]] || [[ "$name" =~ [-_]$ ]]; then
        echo "❌ 错误：名称不能以连字符或下划线开头或结尾，当前：$name" >&2
        return 1
    fi
    
    return 0
}

# 验证输入后缀与期望类型匹配
# 参数：(input, expected_suffix)
# 返回：0（匹配）或1（不匹配），错误信息输出到stderr
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
            echo "❌ 错误：输入后缀 -$current_suffix 与期望后缀 -$expected_suffix 不匹配" >&2
            return 1
            ;;
    esac
}

# 验证epic前缀格式合法性
# 参数：(input)
# 返回：0（合法）或1（非法），警告信息输出到stderr
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
            echo "⚠️ 警告：建议使用标准前缀 epic- 而不是 $prefix" >&2
            return 0
            ;;
        *)
            # 其他情况
            return 1
            ;;
    esac
}

# 为输入补全缺失的后缀标识符
# 参数：(input, required_suffix)
# 返回：补全后的字符串
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

# 强制替换输入的后缀标识符
# 参数：(input, required_suffix)
# 返回：替换后的字符串
replace_suffix_forcefully() {
    local input="$1"
    local required_suffix="$2"  # "e" 或 "ef"
    
    local clean_name
    clean_name=$(strip_suffix_from_input "$input")
    echo "$clean_name-$required_suffix"
}

# 添加标准前缀（如果没有的话）
# 参数：(input)
# 返回：添加前缀后的字符串
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

# 强制设置标准前缀（替换现有前缀）
# 参数：(input)
# 返回：标准前缀后的字符串
force_set_epic_prefix() {
    local input="$1"
    local clean_name
    clean_name=$(strip_epic_prefix_from_input "$input")
    echo "epic-$clean_name"
}