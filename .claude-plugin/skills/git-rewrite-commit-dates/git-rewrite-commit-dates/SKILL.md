---
name: git-rewrite-commit-dates
description: Rewrite commit timestamps from a specified commit (inclusive) to HEAD with evenly spaced times, with the newest commit set to current time. Use when the user asks to batch-adjust git commit times, normalize commit history timestamps, or change dates after a specific commit SHA.
---

# Git Rewrite Commit Dates

## Purpose
批量修改某个提交（包含该提交）到 `HEAD` 的提交时间，要求：
- 避开夜间：`22:00 ~ 09:00`
- 避开周六、周日
- 默认随机间隔（可复现）
- 最新提交时间默认尽量贴近当前时间（若当前在夜间/周末，会自动回退到最近有效工作时间）

## Safety Rules
1. 先创建备份分支。
2. 仅在用户明确同意后改写历史。
3. 改写后提醒用户需要强推（若已推送远端）。

## Inputs
- `start_commit`: 起始提交 SHA（包含）
- `start_time`（可选）：起始时间
  - 若不传：默认使用 `start_commit` 原始提交时间
- `step_minutes`（可选）：相邻提交时间间隔（分钟）
  - 若传：使用固定间隔（仍会避开夜间和周末）
  - 若不传：默认随机间隔
- `random_seed`（可选，默认 `42`）：随机种子，保证同输入可复现

## Workflow
1. 校验当前目录是 git 仓库。
2. 创建备份分支：`backup/rewrite-dates-<timestamp>`。
3. 运行脚本：
   - `python3 ~/.cursor/skills/git-rewrite-commit-dates/scripts/rewrite_commit_dates.py --start-commit <sha> [--start-time "..."] [--step-minutes <n>] [--random-seed <n>]`
4. 校验结果（`git log --format`）。
5. 告知后续操作（本地继续 / 推送时强推）。

## Command Example
```bash
python3 ~/.cursor/skills/git-rewrite-commit-dates/scripts/rewrite_commit_dates.py \
  --start-commit xxxx \
  --start-time "2026-04-01 00:00:00" \
  --step-minutes 5
```

仅传起始提交（自动使用“起始提交原时间 + 工作时段内随机间隔”）：
```bash
python3 ~/.cursor/skills/git-rewrite-commit-dates/scripts/rewrite_commit_dates.py \
  --start-commit xxxx
```

传随机种子（可重复得到同样结果）：
```bash
python3 ~/.cursor/skills/git-rewrite-commit-dates/scripts/rewrite_commit_dates.py \
  --start-commit xxxx \
  --random-seed 20260401
```

## Verification
使用下面命令查看提交时间是否均匀、最新是否为当前：
```bash
git log --date=iso --pretty=format:'%h %ad %s' -n 20
```

## Notes
- 脚本会同时修改 `GIT_AUTHOR_DATE` 和 `GIT_COMMITTER_DATE`。
- 如果 `start_commit` 是根提交，脚本会自动处理范围。
- 改写历史后，旧 SHA 会失效。
