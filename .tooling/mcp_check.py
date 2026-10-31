#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> NoReturn:
    print(
        f"ERROR: {message}",
        file=sys.stderr,
    )
    raise SystemExit(1)


def main() -> int:
    config_path = Path("opencode.json")

    if not config_path.is_file():
        fail("opencode.json not found")

    try:
        data = json.loads(
            config_path.read_text(
                encoding="utf-8",
            )
        )
    except json.JSONDecodeError as exc:
        fail(
            f"invalid opencode.json: {exc}"
        )

    server = (
        data
        .get("mcp", {})
        .get("servers", {})
        .get("openflowkit")
    )

    if not isinstance(server, dict):
        fail(
            "OpenFlowKit MCP is not configured"
        )

    if server.get("disabled") is True:
        fail(
            "OpenFlowKit MCP is disabled"
        )

    command = server.get("command")

    if (
        not isinstance(command, list)
        or not command
        or not all(
            isinstance(item, str)
            and item
            for item in command
        )
    ):
        fail(
            "OpenFlowKit MCP command is invalid"
        )

    cwd_value = server.get("cwd")

    if (
        not isinstance(cwd_value, str)
        or not cwd_value
    ):
        fail(
            "OpenFlowKit MCP cwd is not configured"
        )

    cwd = Path(cwd_value)

    if not cwd.is_dir():
        fail(
            "OpenFlowKit MCP cwd "
            f"does not exist: {cwd}"
        )

    if command[-1] == "mcp":
        probe = (
            command[:-1]
            + ["--version"]
        )
    else:
        probe = (
            command
            + ["--version"]
        )

    try:
        result = subprocess.run(
            probe,
            cwd=cwd,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )

    except FileNotFoundError as exc:
        fail(
            "OpenFlowKit executable "
            f"not found: {exc}"
        )

    except subprocess.TimeoutExpired:
        fail(
            "OpenFlowKit executable "
            "check timed out"
        )

    except subprocess.CalledProcessError as exc:
        if exc.stdout:
            print(
                exc.stdout.rstrip(),
                file=sys.stderr,
            )

        fail(
            "OpenFlowKit executable "
            "check failed"
        )

    print("OpenFlowKit MCP: OK")
    print(f"cwd: {cwd}")
    print(
        "command:",
        " ".join(command),
    )
    print(
        "version:",
        result.stdout.strip(),
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())