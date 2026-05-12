# LiJun's Skills Marketplace

一个为 Claude Code 打造的自定义技能集合。

## 技能列表

### 开发工具 (Development)

| 技能名称 | 描述 |
|---------|------|
| **sunlogin-module** | Sunlogin Linux 交叉模块构建工具，封装 `cmake_build.py`，支持 OpenWrt 模块构建、上传到 devres |
| **sunlogin-service** | Sunlogin Linux 服务端交叉构建工具，封装 `auto_compile.py`，支持服务端编译和上传 |
| **kk-build** | SunloginClient KongKong 控控嵌入式交叉编译构建工具，封装 `kk_build.sh`，支持模块插件、第三方库、kk接口编译和上传 |

### 通用工具 (Utilities)

| 技能名称 | 描述 |
|---------|------|
| **help** | 显示技能帮助信息，通过读取 `SKILL.md` 提取参数和使用说明 |
| **git-rewrite-commit-dates** | 批量重写 git commit 时间戳，支持指定起始 commit 到 HEAD 的均匀分布 |

### 文档生成 (Documentation)

| 技能名称 | 描述 |
|---------|------|
| **code-summary** | 将 git commits 转化为中文技术功能文档，支持 Markdown/DOCX/PDF 输出格式 |
| **tech-doc-generator** | 根据技术方向自动搜索网络资源并生成结构化技术文档，支持性能/代码/通用方向 |

## 安装方式

### 方式一：Plugin Marketplace 安装（推荐）

**仅「添加 marketplace」不会安装插件**，需要再执行一次 **install**（官方文档：[Discover plugins](https://code.claude.com/docs/en/discover-plugins)）。

1. 添加本仓库为 marketplace（Git URL，便于解析插件内的相对路径 `./`）：

```
/plugin marketplace add https://github.com/9527cpp/lijun_skills_marketplace
```

2. 从该 marketplace **安装插件包**（本仓库只发布一个 bundle，内含全部技能）：

```
/plugin install lijun-skills-bundle@lijun-skills
```

3. 重新加载插件：

```
/reload-plugins
```

安装成功后，技能会出现在 Claude Code 的技能加载逻辑中；在对话里自然语言描述任务即可触发（与 `SKILL.md` 里的 `description` 匹配）。文档中的 `/code-summary` 等写法表示「习惯用语」，若你的环境里未注册同名 slash command，可直接说「用 code-summary 总结从 xxx 到 HEAD 的提交」。

#### 若出现 `Plugin xxx not found in marketplace lijun-skills`

说明配置里仍**启用**了旧版 marketplace 的插件名（例如 `code-summary@lijun-skills`），而当前目录里已改为只主推 **`lijun-skills-bundle`**。

**做法一（推荐）**：编辑 `~/.claude/settings.json`（以及项目内 `.claude/settings.local.json` 若存在），在 `enabledPlugins` 中：

- 删除这五个键（若存在）：`code-summary@lijun-skills`、`git-rewrite-commit-dates@lijun-skills`、`help@lijun-skills`、`sunlogin-module@lijun-skills`、`sunlogin-service@lijun-skills`
- 只保留一项：`"lijun-skills-bundle@lijun-skills": true`

保存后执行 `/plugin marketplace update`，再 `/reload-plugins`。

**做法二**：本仓库的 `marketplace.json` 从 1.0.2 起为上述旧名称保留了 **catalog 别名**（与 bundle 同源 `./`），更新 marketplace 后错误应消失。若希望配置干净，仍建议按做法一改为只启用 `lijun-skills-bundle`。

### 方式二：手动安装

1. 下载此仓库
2. 将仓库根目录下 `skills/` 中的目录复制到 `~/.claude/skills/`：

```bash
# 克隆仓库
git clone https://github.com/9527cpp/lijun_skills_marketplace.git
cd lijun_skills_marketplace

# 复制单个技能
cp -r skills/<skill-name> ~/.claude/skills/

# 或复制所有技能
cp -r skills/* ~/.claude/skills/
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

### kk-build

在 SunloginClient 项目根目录执行控控嵌入式构建：

```bash
./kk_build.sh --cross_chain /path/to/toolchain --target <target> [--modules <modules>] [--debug] [--pack]
```

参数说明：
- `--cross_chain <path>`: 交叉编译工具链路径（必填）
- `--target <target>`: 目标平台，如 `arm-openwrt-linux`（必填）
- `--modules <modules>`: 指定模块列表，默认：`desktop audio usbip ssh camera file kk`
- `--main`: 仅编译主程序
- `--3rd [libs]`: 仅编译第三方依赖库，可指定库名（逗号分隔），如 `--3rd openssl,zlib`（可选）
- `--debug`: Debug 模式编译
- `--pack`: 仅执行打包操作
- `--quiet`: 静默模式
- `--no_upload`: 不上传编译结果

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

### tech-doc-generator

根据技术方向自动生成结构化技术文档：

```bash
# 模糊方向（如性能优化）
/tech-doc-generator rockchip mpp 图像质量调优

# 明确主题
/tech-doc-generator Linux V4L2 框架分析

# 代码方向（如驱动分析）
/tech-doc-generator Android Binder 驱动分析
```

文档自动包含：背景介绍、名词解析、原理说明、技术实现、核心流程、注意事项，并根据方向自动添加性能对比或代码架构图。生成完成后可选择保存为 Markdown 文件。

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



## Star History

<a href="https://www.star-history.com/?repos=9527cpp%2Flijun_skills_marketplace&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=9527cpp/lijun_skills_marketplace&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=9527cpp/lijun_skills_marketplace&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=9527cpp/lijun_skills_marketplace&type=date&legend=top-left" />
 </picture>
</a>

