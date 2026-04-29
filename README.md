# LiJun's Skills Marketplace

一个为 Claude Code 打造的自定义技能集合。

## 技能列表

### 开发工具 (Development)

| 技能名称 | 描述 |
|---------|------|
| **sunlogin-module** | Sunlogin Linux 交叉模块构建工具，封装 `cmake_build.py`，支持 OpenWrt 模块构建、上传到 devres |
| **sunlogin-service** | Sunlogin Linux 服务端交叉构建工具，封装 `auto_compile.py`，支持服务端编译和上传 |

### 通用工具 (Utilities)

| 技能名称 | 描述 |
|---------|------|
| **help** | 显示技能帮助信息，通过读取 `SKILL.md` 提取参数和使用说明 |
| **git-rewrite-commit-dates** | 批量重写 git commit 时间戳，支持指定起始 commit 到 HEAD 的均匀分布 |

### 文档生成 (Documentation)

| 技能名称 | 描述 |
|---------|------|
| **code-summary** | 将 git commits 转化为中文技术功能文档，支持 Markdown/DOCX/PDF 输出格式 |

## 安装方式

### 方式一：Plugin Marketplace 安装（推荐）

在 Claude Code 中使用 marketplace 命令安装：

```
/plugin install https://github.com/9527cpp/lijun_skills_marketplace
```

或安装单个技能：

```
/plugin install https://github.com/9527cpp/lijun_skills_marketplace?skill=sunlogin-module
/plugin install https://github.com/9527cpp/lijun_skills_marketplace?skill=code-summary
```

### 方式二：手动安装

1. 下载此仓库
2. 将技能复制到 `~/.claude/skills/` 目录：

```bash
# 克隆仓库
git clone https://github.com/9527cpp/lijun_skills_marketplace.git

# 复制单个技能
cp -r .claude-plugin/skills/<skill-name> ~/.claude/skills/

# 或复制所有技能
cp -r .claude-plugin/skills/* ~/.claude/skills/
```

### 方式三：打包安装

每个技能也可以单独下载 `.skill` 文件安装：

```bash
# 将 .skill 文件放到 ~/.claude/skills/ 目录即可
```

## 使用方法

### sunlogin-module

在 desktop 仓库根目录执行模块构建：

```bash
python ~/.claude/skills/sunlogin-module/scripts/sunlogin_module_build.py -t <target> [-m <module>] [-c <cross_path>] [-r]
```

参数说明：
- `-t <target>`: 目标平台（如 `arm-openwrt-linux`）
- `-m <module>`: 模块名（可选）
- `-c <cross_path>`: 交叉编译路径（可选）
- `-r`: 是否上传到 devres（可选）

### sunlogin-service

在 sunloginclient 仓库根目录执行服务端构建：

```bash
python ~/.claude/skills/sunlogin-service/scripts/sunlogin_service_build.py -t <target> [-c <cross_path>] [-r] [-d]
```

参数说明：
- `-t <target>`: 目标平台
- `-c <cross_path>`: 交叉编译路径（可选）
- `-r`: 是否上传到 devres（可选）
- `-d`: 调试模式（可选）

### help

查看任意技能的帮助信息：

```
skill_name --help
```

例如：`code-summary --help`

### code-summary

将 git commits 转化为中文技术文档：

```bash
# 总结最近 10 个 commit
/code-summary

# 从指定 commit 总结到现在
/code-summary abc1234

# 输出为 Word 文档
/code-summary abc1234 --type doc

# 增量更新已有文档
/code-summary --update abc1234 --output ./docs/feature.md
```

### git-rewrite-commit-dates

批量重写 git commit 时间戳：

```bash
# 从指定 commit 到 HEAD，均匀分布时间
/git-rewrite-commit-dates --start-commit <SHA>

# 自定义时间间隔（分钟）
/git-rewrite-commit-dates --start-commit <SHA> --step-minutes 10

# 预览模式（不实际修改）
/git-rewrite-commit-dates --start-commit <SHA> --dry-run
```

## 技能开发

技能结构：

```
skill-name/
├── SKILL.md           # 技能定义文件
├── scripts/          # 可选：辅助脚本
│   └── *.py
├── references/       # 可选：参考文档
└── assets/          # 可选：静态资源
```

### SKILL.md 结构

```yaml
---
name: skill-name
description: >-
  技能的简短描述，说明用途和触发场景
---

# 技能名称

详细的技能说明...
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License
