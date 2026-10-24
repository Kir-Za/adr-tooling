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


DEFAULT_SECRETS_FILE = Path("config/langfuse.secrets.json")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def env(name: str) -> str:
    value = os.getenv(name)

    if not value:
        fail(f"{name} is not set")

    return value


def load_secrets(
    path: Path = DEFAULT_SECRETS_FILE,
):
    if not path.is_file():
        fail(
            f"Langfuse secrets file not found: {path}"
        )

    try:
        data = json.loads(
            path.read_text(encoding="utf-8")
        )
    except json.JSONDecodeError as error:
        fail(
            f"invalid Langfuse secrets JSON: "
            f"{path}: {error}"
        )

    public_key = data.get("public_key")
    secret_key = data.get("secret_key")

    if (
        not isinstance(public_key, str)
        or not public_key
    ):
        fail(
            f"public_key is missing in {path}"
        )

    if (
        not isinstance(secret_key, str)
        or not secret_key
    ):
        fail(
            f"secret_key is missing in {path}"
        )

    return public_key, secret_key


def extract_prompt_body(path: Path) -> str:
    text = path.read_text(
        encoding="utf-8"
    )

    if not text.startswith("---\n"):
        fail(
            f"frontmatter not found: {path}"
        )

    parts = text.split(
        "---\n",
        2,
    )

    if len(parts) != 3:
        fail(
            f"invalid frontmatter: {path}"
        )

    return (
        parts[2]
        .lstrip("\n")
        .rstrip()
        + "\n"
    )


def authorization() -> str:
    public_key, secret_key = load_secrets()

    raw = (
        f"{public_key}:"
        f"{secret_key}"
    )

    token = base64.b64encode(
        raw.encode("utf-8")
    ).decode("ascii")

    return f"Basic {token}"


def api_request(
    method: str,
    url: str,
    payload=None,
):
    data = None

    if payload is not None:
        data = json.dumps(
            payload
        ).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization":
                authorization(),

            "Content-Type":
                "application/json",
        },
    )

    try:
        with urllib.request.urlopen(
            request
        ) as response:
            raw = (
                response
                .read()
                .decode("utf-8")
            )

            return (
                response.status,
                json.loads(raw)
                if raw
                else {},
            )

    except urllib.error.HTTPError as error:
        raw = (
            error
            .read()
            .decode(
                "utf-8",
                errors="replace",
            )
        )

        return (
            error.code,
            raw,
        )


def get_prompt(
    base_url: str,
    name: str,
    label: str,
):
    encoded_name = urllib.parse.quote(
        name,
        safe="",
    )

    query = urllib.parse.urlencode(
        {
            "label": label,
        }
    )

    return api_request(
        "GET",
        (
            f"{base_url}"
            f"/api/public/v2/prompts/"
            f"{encoded_name}"
            f"?{query}"
        ),
    )


def push_prompt(
    base_url: str,
    name: str,
    label: str,
    template: Path,
):
    local = extract_prompt_body(
        template
    )

    status, remote = get_prompt(
        base_url,
        name,
        label,
    )

    if (
        status == 200
        and isinstance(remote, dict)
        and remote.get("prompt") == local
    ):
        print(
            f"prompt unchanged: {name}"
        )
        return

    if status not in (200, 404):
        fail(
            f"cannot read remote prompt "
            f"{name}: "
            f"HTTP {status}: {remote}"
        )

    payload = {
        "name": name,
        "type": "text",
        "prompt": local,
        "labels": [label],
    }

    status, result = api_request(
        "POST",
        (
            f"{base_url}"
            f"/api/public/v2/prompts"
        ),
        payload,
    )

    if status not in (200, 201):
        fail(
            f"cannot push prompt "
            f"{name}: "
            f"HTTP {status}: {result}"
        )

    if isinstance(result, dict):
        version = result.get(
            "version",
            "?",
        )
    else:
        version = "?"

    print(
        f"prompt pushed: "
        f"{name} "
        f"version={version}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Publish Git-default "
            "agent prompt bodies "
            "to Langfuse."
        )
    )

    parser.add_argument(
        "--name",
        required=True,
    )

    parser.add_argument(
        "--label",
        required=True,
    )

    parser.add_argument(
        "--template",
        required=True,
    )

    args = parser.parse_args()

    base_url = env(
        "LANGFUSE_BASE_URL"
    ).rstrip("/")

    template = Path(
        args.template
    )

    if not template.is_file():
        fail(
            f"template not found: "
            f"{template}"
        )

    push_prompt(
        base_url,
        args.name,
        args.label,
        template,
    )


if __name__ == "__main__":
    main()