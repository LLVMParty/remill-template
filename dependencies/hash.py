#!/usr/bin/env python3
"""Compute a stable cache key for the dependency prefix.

The hash covers the dependency superbuild inputs and the remill submodule commit.
A commit message can opt into reusing an older dependency cache by including one
of:

  reuse_cache=<hash>
  reuse_hash=<hash>
  restore_hash=<hash>
  cache_hash=<hash>
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


def hash_file(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def git(command: str, cwd: Path) -> str:
    args = ["git"] + shlex.split(command)
    result = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"git {command} failed with exit code {result.returncode}: {result.stderr}")
    return result.stdout.rstrip()


def add_file(status: list[str], root: Path, path: Path) -> None:
    if path.exists() and path.is_file():
        try:
            display_path = path.relative_to(root).as_posix()
        except ValueError:
            display_path = path.relative_to(root.parent).as_posix()
        status.append(f"{hash_file(path)} {display_path}")


def add_glob(status: list[str], root: Path, pattern: str) -> None:
    for path in sorted(root.glob(pattern)):
        add_file(status, root, path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--simple", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    repo_root = root.parent

    status: list[str] = []

    # Top-level dependency superbuild inputs. Files under dependencies/remill
    # are intentionally not hashed here: the remill submodule commit below
    # already captures remill's dependency recipes and sleigh patches.
    for name in [
        "CMakeLists.txt",
        "superbuild.cmake",
        "llvm.cmake",
        "llvm-prebuilt.cmake",
    ]:
        add_file(status, root, root / name)
    add_file(status, root, repo_root / ".gitmodules")

    # Include submodule commits. From the dependencies directory, the remill
    # submodule path is simply "remill".
    try:
        submodules = git("submodule status --recursive", root)
        if submodules:
            for line in submodules.splitlines():
                status.append(line.strip())
    except Exception as exc:
        status.append(f"submodule-status-error {exc}")

    final_status = "\n".join(status) + "\n"
    file_hash = hashlib.sha1(final_status.encode("utf-8")).hexdigest()

    # Allow a commit to explicitly restore from an older compatible cache.
    restore_hash = file_hash
    try:
        commit_message = git("log -1 --pretty=format:%s", repo_root)
        match = re.search(r"(?:reuse_cache|reuse_hash|restore_hash|cache_hash)=([0-9a-f]+)", commit_message)
        if match:
            restore_hash = match.group(1)
    except Exception:
        pass

    if args.simple:
        output = f"{file_hash}\n"
    else:
        output = f"file_hash={file_hash}\nrestore_hash={restore_hash}\n"

    sys.stdout.write(output)

    if args.debug:
        sys.stderr.write("Debug output:\n")
        sys.stderr.write(final_status)
        sys.stderr.write(output)
        sys.stderr.flush()


if __name__ == "__main__":
    main()
