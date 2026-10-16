#!/usr/bin/env python3

import os
import re
import sys
from pathlib import Path

VAR_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def render(template_path: Path, output_path: Path) -> None:
    if not template_path.is_file():
        fail(f"template not found: {template_path}")

    content = template_path.read_text(encoding="utf-8")

    missing = sorted({
        match.group(1)
        for match in VAR_PATTERN.finditer(content)
        if match.group(1) not in os.environ
    })

    if missing:
        fail(
            f"missing environment variables for {template_path}: "
            + ", ".join(missing)
        )

    rendered = VAR_PATTERN.sub(
        lambda match: os.environ[match.group(1)],
        content,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)

    current = None
    if output_path.exists():
        current = output_path.read_text(encoding="utf-8")

    if current == rendered:
        print(f"unchanged: {output_path}")
        return

    output_path.write_text(rendered, encoding="utf-8")
    print(f"rendered: {output_path}")


def check(template_path: Path, output_path: Path) -> None:
    if not template_path.is_file():
        fail(f"template not found: {template_path}")

    content = template_path.read_text(encoding="utf-8")

    missing = sorted({
        match.group(1)
        for match in VAR_PATTERN.finditer(content)
        if match.group(1) not in os.environ
    })

    if missing:
        fail(
            f"missing environment variables for {template_path}: "
            + ", ".join(missing)
        )

    expected = VAR_PATTERN.sub(
        lambda match: os.environ[match.group(1)],
        content,
    )

    if not output_path.is_file():
        fail(f"rendered file not found: {output_path}")

    actual = output_path.read_text(encoding="utf-8")

    if actual != expected:
        fail(f"rendered file is out of date: {output_path}")

    print(f"render-check: OK: {output_path}")


def main() -> None:
    if len(sys.argv) != 4:
        fail(
            "usage: render.py <render|check> <template> <output>"
        )

    mode = sys.argv[1]
    template_path = Path(sys.argv[2])
    output_path = Path(sys.argv[3])

    if mode == "render":
        render(template_path, output_path)
    elif mode == "check":
        check(template_path, output_path)
    else:
        fail(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()