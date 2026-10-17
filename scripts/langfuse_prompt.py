#!/usr/bin/env python3

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        fail(f"{name} is not set")
    return value


def extract_prompt_body(path: Path) -> str:
    text = path.read_text(encoding="utf-8")

    if not text.startswith("---\n"):
        fail(f"frontmatter not found: {path}")

    parts = text.split("---\n", 2)

    if len(parts) != 3:
        fail(f"invalid frontmatter: {path}")

    return parts[2].lstrip("\n").rstrip() + "\n"


def authorization() -> str:
    raw = f"{env('LANGFUSE_PUBLIC_KEY')}:{env('LANGFUSE_SECRET_KEY')}"
    token = base64.b64encode(raw.encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def api_request(method: str, url: str, payload=None):
    data = None

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": authorization(),
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        return error.code, raw


def get_prompt(base_url: str, name: str, label: str):
    encoded_name = urllib.parse.quote(name, safe="")
    query = urllib.parse.urlencode({"label": label})

    return api_request(
        "GET",
        f"{base_url}/api/public/v2/prompts/{encoded_name}?{query}",
    )


def push_prompt(base_url: str, name: str, label: str, template: Path):
    local = extract_prompt_body(template)

    status, remote = get_prompt(base_url, name, label)

    if status == 200 and remote.get("prompt") == local:
        print(f"prompt unchanged: {name}")
        return

    if status not in (200, 404):
        fail(f"cannot read remote prompt {name}: HTTP {status}: {remote}")

    payload = {
        "name": name,
        "type": "text",
        "prompt": local,
        "labels": [label],
    }

    status, result = api_request(
        "POST",
        f"{base_url}/api/public/v2/prompts",
        payload,
    )

    if status not in (200, 201):
        fail(f"cannot push prompt {name}: HTTP {status}: {result}")

    print(f"prompt pushed: {name} version={result.get('version', '?')}")


def check_prompt(base_url: str, name: str, label: str, template: Path):
    local = extract_prompt_body(template)

    status, remote = get_prompt(base_url, name, label)

    if status != 200:
        fail(f"prompt not found: {name} label={label}")

    if remote.get("prompt") != local:
        fail(f"prompt differs from Git default: {name}")

    print(
        f"prompt check: OK: {name} "
        f"version={remote.get('version', '?')} "
        f"label={label}"
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("mode", choices=["push", "check"])
    parser.add_argument("--name", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--template", required=True)

    args = parser.parse_args()

    base_url = env("LANGFUSE_BASE_URL").rstrip("/")
    template = Path(args.template)

    if not template.is_file():
        fail(f"template not found: {template}")

    if args.mode == "push":
        push_prompt(base_url, args.name, args.label, template)
    else:
        check_prompt(base_url, args.name, args.label, template)


if __name__ == "__main__":
    main()