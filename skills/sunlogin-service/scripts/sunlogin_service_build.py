#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wrapper for auto_compile.py (sunlogin service cross-build workflow)."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


# 技能安装在用户目录 ~/.claude/skills/，与具体工程解耦；工程根目录 = 运行脚本时的当前工作目录
def repo_root() -> Path:
    return Path.cwd().resolve()


# 未传 -c 时按 -t 选择默认工具链根目录（可被环境变量覆盖）
DEFAULT_CROSS_BY_TARGET = {
    "aarch64-openwrt-linux": "/home/lijun/workspace/sunlogin-orayos/staging_dir/toolchain-aarch64_cortex-a53_gcc-12.3.0_glibc",
    "arm-openwrt-linux": "/home/lijun/workspace/toolchain-arm_cortex-a7+neon-vfpv4_gcc-12.2.0_glibc_eabi",
    "arm-rockchip830-linux-uclibcgnueabihf": "/home/lijun/workspace/toolchain-arm-rockchip830-linux-uclibcgnueabihf",
}

UPLOAD_BASE = "http://devres.oray.net/release/sunlogin/embed/"


def git_short_8(repo: Path) -> str:
    out = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--short=8", "HEAD"],
        text=True,
    ).strip()
    if len(out) < 8:
        full = subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True
        ).strip()
        out = full[:8]
    return out[:8]


def git_branch(repo: Path) -> str:
    out = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--abbrev-ref", "HEAD"],
        text=True,
    ).strip()
    return out


def resolve_cross_path(
    target: str, explicit: str | None
) -> str:
    if explicit:
        return explicit
    env_all = os.environ.get("SUNLOGIN_CROSS_CHAIN_PATH")
    if env_all:
        return env_all
    key = "SUNLOGIN_CROSS_CHAIN_" + target.upper().replace("-", "_")
    env_t = os.environ.get(key)
    if env_t:
        return env_t
    default = DEFAULT_CROSS_BY_TARGET.get(target)
    if default:
        return default
    sys.stderr.write(
        "error: 未提供 -c，且 target=%r 无内置默认路径。\n"
        "请设置 -c、或 SUNLOGIN_CROSS_CHAIN_PATH、或 %s\n"
        % (target, key)
    )
    sys.exit(2)


def main() -> None:
    p = argparse.ArgumentParser(
        description="Sunlogin 服务端交叉构建（封装 auto_compile.py，固定 -p linux -t cli）"
    )
    p.add_argument(
        "-t",
        "--target",
        required=True,
        help="交叉目标：同时作为 auto_compile 的 -a 与 -T",
    )
    p.add_argument(
        "-c",
        "--cross-path",
        default=None,
        help="工具链根目录；传给 auto_compile 为 -c \"-DCROSS_CHAIN_PATH=...,-DCMAKE_VERBOSE_MAKEFILE=ON\"（省略时按 -t 或环境变量解析）",
    )
    p.add_argument(
        "-r",
        "--upload",
        action="store_true",
        help="构建完成后上传；地址为 UPLOAD_BASE + <git_branch>/<git_short_8_sha>",
    )
    p.add_argument(
        "-d",
        "--debug",
        action="store_true",
        help="构建 Debug 版本（默认 Release）",
    )
    args, rest = p.parse_known_args()
    if rest:
        sys.stderr.write("error: 未知参数: %s\n" % " ".join(rest))
        sys.exit(2)

    repo = repo_root()
    auto_compile = repo / "auto_compile.py"
    if not auto_compile.is_file():
        sys.stderr.write(
            "error: 找不到 %s\n请在 sunloginclient 工程根目录下执行本脚本（cwd 即为工程路径）。\n"
            % auto_compile
        )
        sys.exit(2)

    target = args.target
    cross = resolve_cross_path(target, args.cross_path)

    # 构建 cmake_args: -DCROSS_CHAIN_PATH=<path>,-DCMAKE_VERBOSE_MAKEFILE=ON
    cmake_args = "-DCROSS_CHAIN_PATH=%s,-DCMAKE_VERBOSE_MAKEFILE=ON" % cross

    cmd = [
        sys.executable,
        str(auto_compile),
        "-p", "linux",
        "-a", target,
        "-t", "cli",
        "-c", cmake_args,
        "-T", target,
    ]

    if args.upload:
        branch = git_branch(repo)
        sha = git_short_8(repo)
        upload_url = UPLOAD_BASE + branch + "/" + sha
        cmd.extend(["-u", upload_url])

    if args.debug:
        cmd.append("-d")

    os.chdir(repo)
    print("$ " + " ".join(cmd))
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
