# GPF Command Alias

## 目的
为 git-pr-flow 命令创建 gpf 简写版本，提升用户体验。

## 实现方式
在用户的 ~/.local/bin/ 目录下创建符号链接：
```bash
ln -sf ~/.local/bin/git-pr-flow ~/.local/bin/gpf
```

## 验证
```bash
~/.local/bin/gpf --version
# 输出: Git PR Flow v0.1.0-mvp
```

## 使用示例
以下命令等价：
- `gpf init user-auth develop` ↔ `gpf init user-auth develop`
- `gpf start user-auth/login` ↔ `gpf start user-auth/login`
- `git-pr-flow status` ↔ `gpf status`

## 安装说明
这个符号链接应该在安装脚本中自动创建，确保用户安装后可以直接使用 gpf 命令。