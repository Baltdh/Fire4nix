#!/usr/bin/env python3
"""Bounded CI heartbeat for a long genuine WPEWebKit Ninja cross-build.

Keeps all compiler output in its original log. Every interval it publishes
ONLY Ninja's numeric [completed/total] counter, elapsed seconds and log size.
No compiler commands, paths from output, SDK details or secrets are emitted.
Preserves the child exit status, including the GNU timeout code 124.
This does not certify a linked WebKit ELF or any device compatibility.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys
import time

NINJA_COUNTER = re.compile(rb"(?m)^\[\s*(\d+)\s*/\s*(\d+)\s*\]")
TAIL_LIMIT = 65536


def latest_counter(log: Path) -> str:
    try:
        with log.open("rb") as handle:
            handle.seek(0, 2)
            length = handle.tell()
            handle.seek(max(0, length - TAIL_LIMIT))
            tail = handle.read(TAIL_LIMIT)
    except OSError:
        return "not_yet_available"
    candidates = NINJA_COUNTER.findall(tail)
    if not candidates:
        return "not_yet_available"
    built, total = candidates[-1]
    # Limit output format to numeric counters only, never build commands.
    if len(built) > 9 or len(total) > 9:
        return "invalid_counter"
    return built.decode("ascii") + "/" + total.decode("ascii")


def run(log: Path, interval: int, timeout: int, command: list[str]) -> int:
    if not command or not log.parent.is_dir() or log.is_symlink():
        raise ValueError("NEED_SAFE_LOG_PARENT_AND_COMMAND")
    if interval < 1 or interval > 3600 or timeout < 1 or timeout > 14400:
        raise ValueError("INVALID_INTERVAL_OR_BUILD_TIMEOUT")
    start = time.monotonic()
    # GNU timeout matches the original build script: TERM then KILL after 20s.
    argv = ["timeout", "--signal=TERM", "--kill-after=20s", f"{timeout}s", *command]
    with log.open("wb") as output:
        with subprocess.Popen(argv, stdout=output, stderr=subprocess.STDOUT) as child:
            print("WPE_NINJA_HEARTBEAT=STARTED_LOG_ONLY", flush=True)
            while True:
                try:
                    result = child.wait(timeout=interval)
                    break
                except subprocess.TimeoutExpired:
                    try:
                        length = log.stat().st_size
                    except OSError:
                        length = 0
                    print(
                        "WPE_NINJA_PROGRESS=" + latest_counter(log) +
                        f" elapsed_seconds={int(time.monotonic() - start)}" +
                        f" compiler_log_bytes={length}", flush=True
                    )
    print(
        "WPE_NINJA_HEARTBEAT=FINISHED" +
        f" elapsed_seconds={int(time.monotonic() - start)}" +
        " exit_code=" + str(result),
        flush=True,
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--interval", type=int, default=180)
    parser.add_argument("--timeout", type=int, default=10800)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    try:
        return run(args.log, args.interval, args.timeout, command)
    except (OSError, ValueError) as exc:
        print("WPE_NINJA_HEARTBEAT=CONFIGURATION_ERROR:" +
              type(exc).__name__, file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
