# NewGPF 核心公共组件设计 - GitHub集成

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

## 🆕 10. github-check.sh - GitHub CLI 环境检查（通用组件）

### 核心功能
提供统一的GitHub CLI工具检查，供所有需要GitHub集成的命令使用。

### 通用检查方法

```bash
# 🔧 通用的GitHub CLI环境检查（供所有命令使用）
github_check_environment() {
    # 1. 检查gh工具安装
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) 未安装"
        echo "💡 解决方案:"
        echo "   macOS: brew install gh"
        echo "   Ubuntu: sudo apt install gh"
        echo "   Windows: winget install GitHub.CLI"
        echo "   或访问: https://cli.github.com/"
        return 1
    fi
    
    # 2. 检查GitHub认证状态
    if ! gh auth status &> /dev/null; then
        echo "❌ GitHub CLI 未认证"
        echo "💡 解决方案: 运行 gh auth login"
        echo "   选择 GitHub.com"
        echo "   选择 HTTPS 协议"
        echo "   按提示完成认证"
        return 1
    fi
    
    # 3. 检查当前仓库支持
    if ! gh repo view &> /dev/null; then
        echo "❌ 当前目录不是GitHub仓库或无权限访问"
        echo "💡 可能原因:"
        echo "   1. 不是Git仓库"
        echo "   2. 远程仓库不是GitHub"
        echo "   3. 认证账户无仓库权限"
        return 1
    fi
    
    # 4. 检查网络连接
    if ! gh api user &> /dev/null; then
        echo "❌ GitHub网络连接失败"
        echo "💡 可能原因:"
        echo "   1. 网络连接问题"
        echo "   2. GitHub服务不可用"
        echo "   3. 企业防火墙限制"
        return 1
    fi
    
    return 0
}

# 静默检查（供其他组件调用）
github_check_environment_silent() {
    command -v gh &> /dev/null && 
    gh auth status &> /dev/null && 
    gh repo view &> /dev/null && 
    gh api user &> /dev/null
}

# GitHub CLI版本兼容性检查
check_gh_version() {
    local version
    version=$(gh --version | head -1 | awk '{print $3}')
    echo "GitHub CLI版本: $version"
    
    # 检查最低版本要求（2.0.0+）
    if version_compare "$version" "2.0.0" "<"; then
        echo "⚠️ GitHub CLI版本较低，建议升级到 2.0.0+"
        echo "💡 升级命令: gh extension upgrade gh"
    fi
}
```

## 🆕 11. github-pr.sh - GitHub PR 状态检查和操作

### 核心功能
GitHub PR的状态查询、合并检查和创建操作，供pr、status、clean命令使用。

### PR状态查询方法

```bash
# 检查分支是否已有PR
github_pr_get_status() {
    local branch="$1"
    local target_branch="$2"
    
    # 调用通用环境检查
    if ! github_check_environment_silent; then
        return 1
    fi
    
    # 查找PR
    local pr_number
    pr_number=$(gh pr list --head "$branch" --base "$target_branch" --json number --jq '.[0].number' 2>/dev/null)
    
    if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
        echo "$pr_number"
        return 0
    else
        return 1
    fi
}

# 获取PR完整状态信息
github_pr_get_status() {
    local branch="$1"
    local target_branch="$2"
    
    local pr_number
    if ! pr_number=$(github_pr_get_status "$branch" "$target_branch"); then
        echo "no_pr"
        return 1
    fi
    
    # 获取PR详细状态
    local pr_info
    pr_info=$(gh pr view "$pr_number" --json state,reviewDecision,title,url,mergeable 2>/dev/null)
    
    if [[ -z "$pr_info" ]]; then
        echo "error"
        return 1
    fi
    
    echo "$pr_info"
    return 0
}

# 检查PR是否已安全合并（供clean命令使用）
github_pr_get_status() {
    local branch="$1"
    local target_branch="$2"
    
    local pr_info
    pr_info=$(github_pr_get_status "$branch" "$target_branch")
    
    if [[ "$pr_info" == "no_pr" ]]; then
        echo "no_pr_found"
        return 1
    fi
    
    if [[ "$pr_info" == "error" ]]; then
        echo "check_failed"
        return 1
    fi
    
    local state
    state=$(echo "$pr_info" | jq -r '.state')
    
    case "$state" in
        "MERGED")
            echo "safely_merged"
            return 0
            ;;
        "OPEN")
            echo "still_open"
            return 1
            ;;
        "CLOSED")
            echo "closed_not_merged"
            return 1
            ;;
        *)
            echo "unknown_state"
            return 1
            ;;
    esac
}

# 创建PR（供gpf pr命令使用）
create_github_pr() {
    local source_branch="$1"
    local target_branch="$2"
    local issue_numbers="$3"
    
    # 检查环境
    if ! github_check_environment; then
        return 1
    fi
    
    # 构建PR创建命令
    local pr_args=("--base" "$target_branch" "--head" "$source_branch")
    
    # 添加issue关联
    if [[ -n "$issue_numbers" ]]; then
        local body=""
        IFS=',' read -ra issue_array <<< "$issue_numbers"
        for issue in "${issue_array[@]}"; do
            issue=$(echo "$issue" | tr -d ' ')
            if [[ "$issue" =~ ^[0-9]+$ ]]; then
                if [[ -n "$body" ]]; then
                    body="$body, "
                fi
                body="${body}Closes #$issue"
            fi
        done
        
        if [[ -n "$body" ]]; then
            pr_args+=("--body" "$body")
        fi
    fi
    
    # 创建PR
    echo "🚀 创建GitHub PR: $source_branch → $target_branch"
    if gh pr create "${pr_args[@]}"; then
        echo "✅ PR创建成功"
        return 0
    else
        echo "❌ PR创建失败"
        return 1
    fi
}
```

### Status命令集成方法

```bash
# 供status命令调用的PR状态显示
status_show_github_pr_info() {
    local branch="$1"
    local target_branch="$2"
    local show_pr_only="${3:-false}"
    
    echo "🔗 GitHub PR状态:"
    
    # GitHub CLI环境检查
    if ! github_check_environment_silent; then
        echo "   ⚠️ 无法检查（GitHub CLI未配置）"
        echo "   💡 配置方法: gh auth login"
        return 1
    fi
    
    # 获取PR状态
    local pr_info
    pr_info=$(github_pr_get_status "$branch" "$target_branch")
    
    if [[ "$pr_info" == "no_pr" ]]; then
        echo "   📋 PR状态: 未创建"
        echo "   💡 建议: 运行 gpf pr 创建PR"
        if [[ "$show_pr_only" != "true" ]]; then
            echo ""
            echo "🎯 操作权限:"
            echo "   ✅ gpf pr: 可以创建新PR"
        fi
        return 0
    fi
    
    if [[ "$pr_info" == "error" ]]; then
        echo "   ❌ 检查失败（网络或权限问题）"
        return 1
    fi
    
    # 解析PR详细信息
    local state review_decision title url
    state=$(echo "$pr_info" | jq -r '.state')
    review_decision=$(echo "$pr_info" | jq -r '.reviewDecision // "null"')
    title=$(echo "$pr_info" | jq -r '.title')
    url=$(echo "$pr_info" | jq -r '.url')
    
    # 获取PR号码
    local pr_number
    pr_number=$(github_pr_get_status "$branch" "$target_branch")
    
    echo "   📋 PR #$pr_number: $title"
    echo "   🔗 链接: $url"
    
    # 显示详细状态和操作权限
    case "$state" in
        "OPEN")
            case "$review_decision" in
                "APPROVED")
                    echo "   👥 审核状态: ✅ 已审核通过"
                    echo "   🎯 下一步: 等待合并"
                    [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 已有PR存在 | ⚠️ gpf clean: 等待PR合并"
                    ;;
                "REVIEW_REQUIRED"|"null")
                    echo "   👥 审核状态: ⏳ 等待审核"
                    echo "   🎯 下一步: 等待代码审核"
                    [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 已有PR存在 | ❌ gpf clean: 等待审核完成"
                    ;;
                "CHANGES_REQUESTED")
                    echo "   👥 审核状态: 🔄 需要修改"
                    echo "   🎯 下一步: 处理审核意见"
                    [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 已有PR存在 | ❌ gpf clean: 需要处理审核意见"
                    ;;
            esac
            ;;
        "MERGED")
            echo "   ✅ 状态: 已合并"
            echo "   🎯 下一步: 可以清理分支"
            [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 分支已合并 | ✅ gpf clean: 可以安全清理"
            ;;
        "CLOSED")
            echo "   ❌ 状态: 已关闭（未合并）"
            echo "   ⚠️ 代码未合并到目标分支"
            [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: PR已关闭 | ⚠️ gpf clean: 需要确认是否保留代码"
            ;;
    esac
}
```

## 🆕 12. issue-handler.sh - Issue 关联处理

### 核心功能
处理PR与GitHub issue的关联，确保遵循最佳实践。

### Issue关联方法

```bash
# Issue关联检查和处理（供gpf pr命令使用）
handle_issue_association() {
    local branch="$1"
    local cmd_line_issues="$2"  # 来自 --issue 参数
    
    # 1. 命令参数优先
    if [[ -n "$cmd_line_issues" ]]; then
        if validate_issue_numbers "$cmd_line_issues"; then
            echo "🔗 使用命令行指定的issue: $cmd_line_issues"
            echo "$cmd_line_issues"
            return 0
        else
            echo "❌ Issue号格式错误: $cmd_line_issues"
            echo "💡 正确格式: --issue 123 或 --issue 123,456"
            return 1
        fi
    fi
    
    # 2. 从分支名自动解析
    local auto_issue
    if auto_issue=$(extract_issue_from_branch_name "$branch"); then
        echo "🔗 从分支名检测到issue: #$auto_issue"
        echo "$auto_issue"
        return 0
    fi
    
    # 3. 交互式输入（AI友好设计）
    if is_non_interactive; then
        echo "❌ 非交互式环境中必须通过 --issue 参数指定issue"
        echo "💡 示例: gpf pr --issue 123,456"
        return 1
    fi
    
    echo "⚠️ PR最佳实践要求关联GitHub issue"
    echo "请输入相关的issue编号（多个用逗号分隔）："
    read -r user_issues
    
    if [[ -z "$user_issues" ]]; then
        echo "❌ 必须关联issue才能创建PR"
        echo "💡 或使用: gpf pr --issue <numbers>"
        return 1
    fi
    
    if validate_issue_numbers "$user_issues"; then
        echo "$user_issues"
        return 0
    else
        echo "❌ Issue号格式错误，请重新输入"
        return 1
    fi
}

# 从分支名解析issue号
extract_issue_from_branch_name() {
    local branch="$1"
    
    # 匹配格式: epic-auth-123-e 或 epic-auth-e-login-456-ef
    if [[ "$branch" =~ -([0-9]+)-(e|ef)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# 验证issue号码格式
validate_issue_numbers() {
    local issues="$1"
    
    # 移除所有空格
    issues=$(echo "$issues" | tr -d ' ')
    
    # 检查是否为空
    if [[ -z "$issues" ]]; then
        return 1
    fi
    
    # 分割并验证每个issue号
    IFS=',' read -ra issue_array <<< "$issues"
    for issue in "${issue_array[@]}"; do
        if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
            echo "❌ 无效的issue号: $issue"
            return 1
        fi
    done
    
    return 0
}

# 检查issue是否存在（可选功能）
verify_issues_exist() {
    local issues="$1"
    
    if ! github_check_environment_silent; then
        echo "⚠️ 无法验证issue存在性（GitHub CLI不可用）"
        return 0  # 不阻断流程
    fi
    
    IFS=',' read -ra issue_array <<< "$issues"
    for issue in "${issue_array[@]}"; do
        issue=$(echo "$issue" | tr -d ' ')
        if ! gh issue view "$issue" >/dev/null 2>&1; then
            echo "⚠️ Issue #$issue 可能不存在或无权限访问"
            echo "是否继续？(y/N)"
            read -r confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || return 1
        fi
    done
    
    return 0
}
```