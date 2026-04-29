#!/usr/bin/env python3
import argparse
import datetime as dt
import random
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


def parse_datetime(value: str) -> dt.datetime:
    # Accept: "YYYY-mm-dd HH:MM:SS", ISO8601, or "YYYY-mm-dd"
    v = value.strip()
    if "T" in v:
        v = v.replace("Z", "+00:00")
        t = dt.datetime.fromisoformat(v)
    else:
        try:
            t = dt.datetime.strptime(v, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            t = dt.datetime.strptime(v, "%Y-%m-%d")
    if t.tzinfo is None:
        # Use local timezone for naive inputs.
        t = t.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
    return t


def get_commit_time(sha: str) -> dt.datetime:
    # Use committer time as commit time.
    iso = run(["git", "show", "-s", "--format=%cI", sha]).strip()
    return parse_datetime(iso)


def is_business_time(t: dt.datetime) -> bool:
    return t.weekday() < 5 and 9 <= t.hour < 22


def next_business_start(t: dt.datetime) -> dt.datetime:
    t = t.replace(minute=0, second=0, microsecond=0)
    while True:
        if t.weekday() >= 5:
            # move to next Monday 09:00
            days = 7 - t.weekday()
            t = (t + dt.timedelta(days=days)).replace(hour=9, minute=0, second=0, microsecond=0)
            continue
        if t.hour < 9:
            return t.replace(hour=9, minute=0, second=0, microsecond=0)
        if t.hour >= 22:
            t = (t + dt.timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
            continue
        return t


def prev_business_end(t: dt.datetime) -> dt.datetime:
    # returns a valid time within business window, as latest possible <= t
    t = t.replace(microsecond=0)
    while True:
        if t.weekday() >= 5:
            # back to Friday 21:59:59
            days = t.weekday() - 4
            t = (t - dt.timedelta(days=days)).replace(hour=21, minute=59, second=59, microsecond=0)
            continue
        if t.hour < 9:
            t = (t - dt.timedelta(days=1)).replace(hour=21, minute=59, second=59, microsecond=0)
            continue
        if t.hour >= 22:
            return t.replace(hour=21, minute=59, second=59, microsecond=0)
        return t


def business_segments(start_time: dt.datetime, end_time: dt.datetime):
    cur = start_time.date()
    end_d = end_time.date()
    segments = []
    while cur <= end_d:
        day_start = dt.datetime.combine(cur, dt.time(9, 0, 0), tzinfo=start_time.tzinfo)
        day_end = dt.datetime.combine(cur, dt.time(22, 0, 0), tzinfo=start_time.tzinfo)
        if cur.weekday() < 5:
            s = max(day_start, start_time)
            e = min(day_end, end_time)
            if e > s:
                segments.append((s, e))
        cur = cur + dt.timedelta(days=1)
    return segments


def offset_to_time(segments, off_seconds: float) -> dt.datetime:
    rem = off_seconds
    for s, e in segments:
        span = (e - s).total_seconds()
        if rem <= span:
            return s + dt.timedelta(seconds=rem)
        rem -= span
    return segments[-1][1]


def random_business_timeline(start_time: dt.datetime, end_time: dt.datetime, n: int, seed: int):
    if n == 1:
        return [end_time]
    segments = business_segments(start_time, end_time)
    if not segments:
        raise RuntimeError("No available business-time window between start and end.")
    total = sum((e - s).total_seconds() for s, e in segments)
    if total <= 0:
        raise RuntimeError("No available positive business-time duration.")

    rng = random.Random(seed)
    # Keep first and last fixed, randomize middle commits.
    mids = [rng.random() * total for _ in range(max(0, n - 2))]
    offs = [0.0] + sorted(mids) + [total]
    return [offset_to_time(segments, x) for x in offs]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rewrite commit dates from start commit (inclusive) to HEAD. "
        "Newest commit will be current time; commits are evenly spaced."
    )
    parser.add_argument("--start-commit", required=True, help="Start commit SHA (inclusive)")
    parser.add_argument(
        "--start-time",
        help="Start time. If omitted, use start commit original time. "
             "Examples: '2026-04-01 00:00:00', '2026-04-01', '2026-04-01T08:00:00+08:00'",
    )
    parser.add_argument(
        "--step-minutes",
        type=int,
        default=None,
        help="Spacing minutes between commits. If omitted, use random spacing inside business hours.",
    )
    parser.add_argument(
        "--random-seed",
        type=int,
        default=42,
        help="Random seed for reproducible randomized spacing.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Show planned dates without rewriting")
    args = parser.parse_args()

    if args.step_minutes is not None and args.step_minutes <= 0:
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

    now = dt.datetime.now().astimezone()
    if args.start_time:
        start_time = parse_datetime(args.start_time)
    else:
        start_time = get_commit_time(args.start_commit).astimezone()

    end_time = prev_business_end(now)
    if end_time != now:
        print(f"Note: current time is outside business window, use latest valid time: {end_time}")
    start_time = next_business_start(start_time)

    if start_time > end_time:
        print("No valid business-time range between start-time and now.", file=sys.stderr)
        return 2

    if len(commits) == 1:
        dates = [end_time]
        step = dt.timedelta(0)
    elif args.step_minutes is not None:
        # Fixed step mode (still constrained to business time by clamping final point).
        step = dt.timedelta(minutes=args.step_minutes)
        raw = [start_time + i * step for i in range(len(commits))]
        dates = []
        last = None
        for t in raw:
            tt = next_business_start(t)
            if tt > end_time:
                tt = end_time
            if last and tt <= last:
                tt = next_business_start(last + dt.timedelta(minutes=1))
                if tt > end_time:
                    tt = end_time
            dates.append(tt)
            last = tt
        dates[-1] = end_time
    else:
        # Randomized spacing mode inside workday windows.
        dates = random_business_timeline(start_time, end_time, len(commits), args.random_seed)
        total = dates[-1] - dates[0]
        step = total / (len(commits) - 1)

    mapping = {}
    for sha, ts in zip(commits, dates):
        # Git accepts RFC2822-like; keep timezone explicit.
        mapping[sha] = ts.strftime("%Y-%m-%d %H:%M:%S %z")

    print(f"Commits to rewrite: {len(commits)}")
    print(f"Oldest in range : {commits[0]}")
    print(f"Newest in range : {commits[-1]}")
    print(f"Start target    : {mapping[commits[0]]}")
    print(f"Newest target   : {mapping[commits[-1]]}")
    print(f"Step seconds    : {step.total_seconds():.3f}")

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
