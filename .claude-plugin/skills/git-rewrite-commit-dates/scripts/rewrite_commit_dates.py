#!/usr/bin/env python3
import argparse
import datetime as dt
import os
import subprocess
import sys
from typing import List


def run(cmd: List[str], check: bool = True) -> str:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{p.stderr.strip()}")
    return p.stdout.strip()


def in_git_repo() -> bool:
    try:
        out = run(["git", "rev-parse", "--is-inside-work-tree"])
        return out == "true"
    except Exception:
        return False


def commit_exists(sha: str) -> bool:
    p = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return p.returncode == 0


def get_commits_inclusive(start_sha: str) -> List[str]:
    # Need range including start commit.
    parent = run(["git", "rev-list", "--parents", "-n", "1", start_sha]).split()
    if len(parent) > 1:
        rev_range = f"{start_sha}^..HEAD"
    else:
        rev_range = "HEAD"
    commits = run(["git", "rev-list", "--reverse", rev_range]).splitlines()
    if start_sha in commits:
        idx = commits.index(start_sha)
        return commits[idx:]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rewrite commit dates from start commit (inclusive) to HEAD. "
        "Newest commit will be current time; commits are evenly spaced."
    )
    parser.add_argument("--start-commit", required=True, help="Start commit SHA (inclusive)")
    parser.add_argument("--step-minutes", type=int, default=5, help="Spacing minutes between commits")
    parser.add_argument("--dry-run", action="store_true", help="Show planned dates without rewriting")
    args = parser.parse_args()

    if args.step_minutes <= 0:
        print("step-minutes must be > 0", file=sys.stderr)
        return 2

    if not in_git_repo():
        print("Current directory is not a git repository.", file=sys.stderr)
        return 2

    if not commit_exists(args.start_commit):
        print(f"Start commit not found: {args.start_commit}", file=sys.stderr)
        return 2

    commits = get_commits_inclusive(args.start_commit)
    if not commits:
        print("No commits found from start commit to HEAD.", file=sys.stderr)
        return 2

    now = dt.datetime.now(dt.timezone.utc)
    step = dt.timedelta(minutes=args.step_minutes)
    start_time = now - step * (len(commits) - 1)
    dates = [start_time + i * step for i in range(len(commits))]

    mapping = {}
    for sha, ts in zip(commits, dates):
        # Git accepts RFC2822-like; keep timezone explicit.
        mapping[sha] = ts.strftime("%Y-%m-%d %H:%M:%S %z")

    print(f"Commits to rewrite: {len(commits)}")
    print(f"Oldest in range : {commits[0]}")
    print(f"Newest in range : {commits[-1]}")
    print(f"Newest target   : {mapping[commits[-1]]}")
    print(f"Step minutes    : {args.step_minutes}")

    if args.dry_run:
        print("\nPlan preview:")
        for sha in commits:
            print(f"{sha} -> {mapping[sha]}")
        return 0

    env_filter_lines = [
        "case \"$GIT_COMMIT\" in",
    ]
    for sha in commits:
        d = mapping[sha]
        env_filter_lines.append(f"{sha})")
        env_filter_lines.append(f"  export GIT_AUTHOR_DATE='{d}';")
        env_filter_lines.append(f"  export GIT_COMMITTER_DATE='{d}';")
        env_filter_lines.append("  ;;")
    env_filter_lines.append("esac")
    env_filter = "\n".join(env_filter_lines)

    # Run filter-branch only on the affected range.
    parent = run(["git", "rev-list", "--parents", "-n", "1", args.start_commit]).split()
    if len(parent) > 1:
        rev_range = f"{args.start_commit}^..HEAD"
    else:
        rev_range = "HEAD"

    cmd = [
        "git",
        "filter-branch",
        "-f",
        "--env-filter",
        env_filter,
        rev_range,
    ]
    print("\nRewriting history...")
    run(cmd, check=True)
    print("Done.")
    print("Tip: inspect with:")
    print("  git log --date=iso --pretty=format:'%h %ad %s'")
    print("If already pushed, use force push carefully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
