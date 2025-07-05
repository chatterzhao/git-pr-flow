# GPF 核心公共组件设计 - 用户界面

> 📖 **相关文档**: [主文档](../../README.md) | [架构设计](../ARCHITECTURE.md) | [命令详细](../COMMANDS.md) | [术语表](../术语表.md) | [核心组件索引](../CORE-COMPONENTS.md)

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

## 7. ui.sh - 用户界面

### 核心功能
统一的用户界面输出，避免耦合。

### 基础输出方法

```bash
# 信息输出
ui_info() {
    local message="$1"
    echo "ℹ️ $message"
}

# 成功信息
ui_success() {
    local message="$1"
    echo "✅ $message"
}

# 错误信息（包含解决方案）
ui_error() {
    local message="$1"
    local solution="${2:-}"
    
    echo "❌ 错误：$message" >&2
    if [[ -n "$solution" ]]; then
        echo "💡 建议：$solution" >&2
    fi
}

# 警告信息
ui_warning() {
    local message="$1"
    echo "⚠️ 警告：$message" >&2
}

# 确认操作
ui_confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        echo -n "$message (Y/n): "
    else
        echo -n "$message (y/N): "
    fi
    
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        [nN]|[nN][oO])
            return 1
            ;;
        "")
            [[ "$default" == "y" ]]
            ;;
        *)
            return 1
            ;;
    esac
}
```