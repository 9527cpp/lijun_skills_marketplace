#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wrapper for deps/slpackage/script/cmake_build.py (sunlogin cross-build workflow)."""

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

UPLOAD_BASE = "http://devres.oray.net/oraylibs/sunlogin/sl-"


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


def infer_module_from_include(repo: Path) -> str:
    inc = repo / "include"
    if not inc.is_dir():
        sys.stderr.write("error: include/ 不存在，无法推断 -m\n")
        sys.exit(2)
    clients = sorted(
        p.name for p in inc.iterdir() if p.is_dir() and p.name.startswith("client_")
    )
    if len(clients) == 0:
        sys.stderr.write("error: include/ 下无 client_* 目录，请显式指定 -m\n")
        sys.exit(2)
    if len(clients) > 1:
        sys.stderr.write(
            "error: include/ 下存在多个 client_*：%s，请显式指定 -m\n"
            % ", ".join(clients)
        )
        sys.exit(2)
    return clients[0]


def resolve_cross_path(
    target: str, explicit: str | None, skip_cross: bool
) -> str | None:
    if skip_cross:
        return None
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
        "请设置 -c、或 SUNLOGIN_CROSS_CHAIN_PATH、或 %s，或改用 --no-cross-path\n"
        % (target, key)
    )
    sys.exit(2)


def module_to_upload_slug(module: str) -> str:
    return module.replace("_", "-")


def main() -> None:
    p = argparse.ArgumentParser(
        description="Sunlogin 交叉编译模块（-n 固定为当前 HEAD 的 8 位短 SHA，不可改）"
    )
    p.add_argument(
        "-t",
        "--target",
        required=True,
        help="交叉目标：同时作为 cmake_build 的 -a 与 -t",
    )
    p.add_argument(
        "-m",
        "--module",
        default=None,
        help="模块名（如 client_desktop）；省略时在 include/ 下需唯一 client_*",
    )
    p.add_argument(
        "-c",
        "--cross-path",
        default=None,
        help="工具链根目录；传给 cmake 为 -DCROSS_CHAIN_PATH=...（省略时按 -t 或环境变量解析）",
    )
    p.add_argument(
        "--no-cross-path",
        action="store_true",
        help="不传 -DCROSS_CHAIN_PATH，使用 PATH 中的 ${SL_TOOLCHAIN}-gcc（见 deps/slpackage/cmake/toolchain.cmake）",
    )
    p.add_argument(
        "-r",
        "--upload",
        action="store_true",
        help="构建完成后上传；地址为 %s<module 下划线改横杠>" % UPLOAD_BASE,
    )
    args, rest = p.parse_known_args()
    if rest:
        sys.stderr.write("error: 未知参数: %s\n" % " ".join(rest))
        sys.exit(2)
    if args.no_cross_path and args.cross_path:
        sys.stderr.write("error: 不能同时使用 -c 与 --no-cross-path\n")
        sys.exit(2)

    repo = repo_root()
    cmake_build = repo / "deps" / "slpackage" / "script" / "cmake_build.py"
    if not cmake_build.is_file():
        sys.stderr.write(
            "error: 找不到 %s\n请在 desktop 工程根目录下执行本脚本（cwd 即为工程路径）。\n"
            % cmake_build
        )
        sys.exit(2)

    target = args.target
    module = args.module or infer_module_from_include(repo)
    cross = resolve_cross_path(target, args.cross_path, args.no_cross_path)
    n = git_short_8(repo)

    cmd = [
        sys.executable,
        str(cmake_build),
        "-p",
        "linux",
        "-a",
        target,
        "-t",
        target,
        "-m",
        module,
        "-n",
        n,
    ]
    if cross is not None:
        cmd.extend(["-c", "-DCROSS_CHAIN_PATH=%s" % cross])
    if args.upload:
        cmd.extend(["-r", UPLOAD_BASE + module_to_upload_slug(module)])

    os.chdir(repo)
    print("$ " + " ".join(cmd))
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
