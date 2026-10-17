#!/usr/bin/env python3

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


VAR_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default)


def split_template(path: Path):
    text = path.read_text(encoding="utf-8")

    if not text.startswith("---\n"):
        fail(f"frontmatter not found: {path}")

    parts = text.split("---\n", 2)

    if len(parts) != 3:
        fail(f"invalid frontmatter: {path}")

    frontmatter = "---\n" + parts[1] + "---\n"
    body = parts[2].lstrip("\n").rstrip() + "\n"

    return frontmatter, body


def substitute(text: str) -> str:
    missing = sorted({
        match.group(1)
        for match in VAR_PATTERN.finditer(text)
        if match.group(1) not in os.environ
    })

    if missing:
        fail(
            "missing environment variables: "
            + ", ".join(missing)
        )

    return VAR_PATTERN.sub(
        lambda match: os.environ[match.group(1)],
        text,
    )


def auth_header() -> str:
    public_key = env("LANGFUSE_PUBLIC_KEY")
    secret_key = env("LANGFUSE_SECRET_KEY")

    if not public_key or not secret_key:
        raise RuntimeError("Langfuse credentials are not set")

    raw = f"{public_key}:{secret_key}"
    encoded = base64.b64encode(
        raw.encode("utf-8")
    ).decode("ascii")

    return f"Basic {encoded}"


def fetch_langfuse_prompt(
    base_url: str,
    name: str,
    version: str,
):
    encoded_name = urllib.parse.quote(name, safe="")

    if version:
        query = urllib.parse.urlencode({
            "version": version,
        })
        selector = f"version={version}"
    else:
        query = urllib.parse.urlencode({
            "label": "latest",
        })
        selector = "latest"

    url = (
        f"{base_url.rstrip('/')}"
        f"/api/public/v2/prompts/{encoded_name}"
        f"?{query}"
    )

    request = urllib.request.Request(
        url,
        headers={
            "Authorization": auth_header(),
            "Accept": "application/json",
        },
        method="GET",
    )

    with urllib.request.urlopen(
        request,
        timeout=5,
    ) as response:
        result = json.loads(
            response.read().decode("utf-8")
        )

    prompt = result.get("prompt")

    if not isinstance(prompt, str):
        raise RuntimeError(
            f"Langfuse prompt is not a text prompt: {name}"
        )

    remote_version = result.get("version", "?")

    return (
        prompt.rstrip() + "\n",
        remote_version,
        selector,
    )


def resolve_body(
    default_body: str,
    prompt_name: str,
    prompt_version: str,
):
    if env("LANGFUSE_ENABLED", "0") != "1":
        return default_body, "git-default"

    base_url = env("LANGFUSE_BASE_URL")

    if not base_url:
        print(
            f"WARNING: LANGFUSE_BASE_URL is not set; "
            f"using Git default for {prompt_name}",
            file=sys.stderr,
        )
        return default_body, "git-default"

    try:
        body, remote_version, selector = fetch_langfuse_prompt(
            base_url,
            prompt_name,
            prompt_version,
        )

        return (
            body,
            f"langfuse:{prompt_name}:"
            f"v{remote_version}:{selector}",
        )

    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        TimeoutError,
        RuntimeError,
        json.JSONDecodeError,
    ) as error:
        print(
            f"WARNING: cannot load Langfuse prompt "
            f"{prompt_name}: {error}; "
            f"using Git default",
            file=sys.stderr,
        )

        return default_body, "git-default"


def expected_content(
    template: Path,
    prompt_name: str,
    prompt_version: str,
):
    frontmatter, default_body = split_template(template)

    body, source = resolve_body(
        default_body,
        prompt_name,
        prompt_version,
    )

    content = (
        substitute(frontmatter).rstrip()
        + "\n\n"
        + substitute(body).lstrip()
    )

    return content, source


def render(
    template: Path,
    output: Path,
    prompt_name: str,
    prompt_version: str,
):
    content, source = expected_content(
        template,
        prompt_name,
        prompt_version,
    )

    output.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    if (
        output.exists()
        and output.read_text(encoding="utf-8") == content
    ):
        print(
            f"unchanged: {output} [{source}]"
        )
        return

    output.write_text(
        content,
        encoding="utf-8",
    )

    print(
        f"rendered: {output} [{source}]"
    )


def check(
    template: Path,
    output: Path,
    prompt_name: str,
    prompt_version: str,
):
    expected, source = expected_content(
        template,
        prompt_name,
        prompt_version,
    )

    if not output.is_file():
        fail(f"rendered file not found: {output}")

    actual = output.read_text(
        encoding="utf-8"
    )

    if actual != expected:
        fail(
            f"rendered agent is out of date: {output}"
        )

    print(
        f"render-check: OK: {output} [{source}]"
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "mode",
        choices=["render", "check"],
    )

    parser.add_argument(
        "--template",
        required=True,
    )

    parser.add_argument(
        "--output",
        required=True,
    )

    parser.add_argument(
        "--prompt-name",
        required=True,
    )

    parser.add_argument(
        "--prompt-version",
        default="",
    )

    args = parser.parse_args()

    template = Path(args.template)
    output = Path(args.output)

    if not template.is_file():
        fail(f"template not found: {template}")

    if args.mode == "render":
        render(
            template,
            output,
            args.prompt_name,
            args.prompt_version,
        )
    else:
        check(
            template,
            output,
            args.prompt_name,
            args.prompt_version,
        )


if __name__ == "__main__":
    main()