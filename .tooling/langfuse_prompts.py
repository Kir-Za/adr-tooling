#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class Error(RuntimeError):
    pass


def split_document(
    path: Path,
) -> tuple[str, str]:
    text = path.read_text(
        encoding="utf-8",
    )

    if not text.startswith("---\n"):
        raise Error(
            f"frontmatter not found: {path}"
        )

    parts = text.split(
        "---\n",
        2,
    )

    if len(parts) != 3:
        raise Error(
            f"invalid frontmatter: {path}"
        )

    frontmatter = (
        "---\n"
        + parts[1]
        + "---\n"
    )

    body = (
        parts[2]
        .lstrip("\n")
        .rstrip()
        + "\n"
    )

    return frontmatter, body


def load_config(
    path: Path,
) -> dict[str, str]:
    result: dict[str, str] = {}

    if not path.is_file():
        raise Error(
            f"config not found: {path}"
        )

    for raw in path.read_text(
        encoding="utf-8",
    ).splitlines():
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        if ":=" in line:
            key, value = line.split(
                ":=",
                1,
            )
        elif "=" in line:
            key, value = line.split(
                "=",
                1,
            )
        else:
            continue

        result[key.strip()] = (
            value.strip()
        )

    return result


def load_credentials(
    path: Path,
) -> dict:
    try:
        data = json.loads(
            path.read_text(
                encoding="utf-8",
            )
        )
    except FileNotFoundError as exc:
        raise Error(
            f"Langfuse secrets not found: {path}"
        ) from exc

    if (
        not data.get("public_key")
        or not data.get("secret_key")
    ):
        raise Error(
            "Langfuse credentials missing"
        )

    return data


def auth_header(
    credentials: dict,
) -> str:
    token = base64.b64encode(
        (
            credentials["public_key"]
            + ":"
            + credentials["secret_key"]
        ).encode()
    ).decode()

    return "Basic " + token


def request(
    method: str,
    url: str,
    credentials: dict,
    payload=None,
):
    data = (
        json.dumps(payload).encode()
        if payload is not None
        else None
    )

    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization":
                auth_header(
                    credentials
                ),
            "Accept":
                "application/json",
            "Content-Type":
                "application/json",
        },
    )

    try:
        with urllib.request.urlopen(
            req,
            timeout=10,
        ) as response:
            raw = (
                response
                .read()
                .decode()
            )

            return (
                response.status,
                json.loads(raw)
                if raw
                else {},
            )

    except urllib.error.HTTPError as exc:
        raw = (
            exc.read()
            .decode(
                errors="replace",
            )
        )

        try:
            body = (
                json.loads(raw)
                if raw
                else {}
            )
        except json.JSONDecodeError:
            body = raw

        return exc.code, body


def runtime_items(
    root: Path,
    manifest: dict,
):
    for agent_id, entry in sorted(
        manifest.get(
            "agents",
            {},
        ).items()
    ):
        yield (
            "agent",
            agent_id,
            entry,
            root
            / ".opencode"
            / "agents"
            / f"{agent_id}.md",
        )

    for skill_id, entry in sorted(
        manifest.get(
            "skills",
            {},
        ).items()
    ):
        yield (
            "skill",
            skill_id,
            entry,
            root
            / ".opencode"
            / "skills"
            / skill_id
            / "SKILL.md",
        )


def fetch_prompt(
    base_url: str,
    label: str,
    credentials: dict,
    name: str,
):
    encoded = urllib.parse.quote(
        name,
        safe="",
    )

    query = urllib.parse.urlencode(
        {
            "label": label,
        }
    )

    status, result = request(
        "GET",
        (
            base_url.rstrip("/")
            + "/api/public/v2/prompts/"
            + encoded
            + "?"
            + query
        ),
        credentials,
    )

    if status != 200:
        raise Error(
            f"cannot fetch {name}: "
            f"HTTP {status}: {result}"
        )

    prompt = result.get(
        "prompt"
    )

    if not isinstance(
        prompt,
        str,
    ):
        raise Error(
            "Langfuse prompt is not "
            f"text: {name}"
        )

    version = result.get(
        "version"
    )

    return (
        prompt.rstrip()
        + "\n",
        (
            version
            if isinstance(
                version,
                int,
            )
            else None
        ),
    )


def push_prompt(
    base_url: str,
    label: str,
    credentials: dict,
    name: str,
    body: str,
):
    encoded = urllib.parse.quote(
        name,
        safe="",
    )

    query = urllib.parse.urlencode(
        {
            "label": label,
        }
    )

    status, remote = request(
        "GET",
        (
            base_url.rstrip("/")
            + "/api/public/v2/prompts/"
            + encoded
            + "?"
            + query
        ),
        credentials,
    )

    if (
        status == 200
        and isinstance(
            remote,
            dict,
        )
        and remote.get(
            "prompt"
        ) == body
    ):
        version = remote.get(
            "version"
        )

        return (
            False,
            (
                version
                if isinstance(
                    version,
                    int,
                )
                else None
            ),
        )

    if status not in (
        200,
        404,
    ):
        raise Error(
            "cannot read remote "
            f"prompt {name}: "
            f"HTTP {status}: "
            f"{remote}"
        )

    status, result = request(
        "POST",
        (
            base_url.rstrip("/")
            + "/api/public/v2/prompts"
        ),
        credentials,
        {
            "name": name,
            "type": "text",
            "prompt": body,
            "labels": [
                label,
            ],
        },
    )

    if status not in (
        200,
        201,
    ):
        raise Error(
            f"cannot push {name}: "
            f"HTTP {status}: {result}"
        )

    version = (
        result.get("version")
        if isinstance(
            result,
            dict,
        )
        else None
    )

    return (
        True,
        (
            version
            if isinstance(
                version,
                int,
            )
            else None
        ),
    )


def save_manifest(
    path: Path,
    manifest: dict,
) -> None:
    path.write_text(
        json.dumps(
            manifest,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def langfuse_settings(
    root: Path,
    config: dict[str, str],
):
    base_url = config.get(
        "LANGFUSE_BASE_URL",
        "",
    ).rstrip("/")

    if not base_url:
        raise Error(
            "LANGFUSE_BASE_URL "
            "is not configured"
        )

    label = config.get(
        "LANGFUSE_PROMPT_LABEL",
        "production",
    )

    secrets_file = Path(
        config.get(
            "LANGFUSE_SECRETS_FILE",
            "config/langfuse.secrets.json",
        )
    )

    if not secrets_file.is_absolute():
        secrets_file = (
            root
            / secrets_file
        )

    credentials = load_credentials(
        secrets_file
    )

    return (
        base_url,
        label,
        credentials,
    )


def check(
    root: Path,
    config: dict[str, str],
) -> int:
    if (
        config.get(
            "LANGFUSE_ENABLED",
            "0",
        )
        != "1"
    ):
        print(
            "Langfuse: disabled"
        )
        return 0

    (
        base_url,
        _label,
        credentials,
    ) = langfuse_settings(
        root,
        config,
    )

    status, _ = request(
        "GET",
        (
            base_url
            + "/api/public/v2/prompts"
        ),
        credentials,
    )

    if status not in (
        200,
        400,
        404,
    ):
        raise Error(
            "Langfuse API check failed: "
            f"HTTP {status}"
        )

    print("Langfuse: OK")

    return 0


def pull(
    root: Path,
    config: dict[str, str],
) -> int:
    if (
        config.get(
            "LANGFUSE_ENABLED",
            "0",
        )
        != "1"
    ):
        print(
            "Langfuse: disabled; "
            "pull skipped"
        )
        return 0

    manifest_path = (
        root
        / ".opencode"
        / "prompt-manifest.json"
    )

    manifest = json.loads(
        manifest_path.read_text(
            encoding="utf-8",
        )
    )

    (
        base_url,
        label,
        credentials,
    ) = langfuse_settings(
        root,
        config,
    )

    changed = 0

    for (
        kind,
        item_id,
        entry,
        path,
    ) in runtime_items(
        root,
        manifest,
    ):
        name = entry.get(
            "name"
        )

        if not name:
            raise Error(
                "prompt name missing for "
                f"{kind}:{item_id}"
            )

        if not path.is_file():
            raise Error(
                "runtime file not found: "
                f"{path}"
            )

        (
            frontmatter,
            local_body,
        ) = split_document(
            path
        )

        (
            remote_body,
            version,
        ) = fetch_prompt(
            base_url,
            label,
            credentials,
            name,
        )

        if (
            local_body
            == remote_body
        ):
            print(
                f"unchanged: "
                f"{kind}:{item_id} "
                f"{name} "
                f"version={version}"
            )
        else:
            path.write_text(
                (
                    frontmatter
                    + "\n"
                    + remote_body
                ),
                encoding="utf-8",
            )

            changed += 1

            print(
                f"pulled: "
                f"{kind}:{item_id} "
                f"{name} "
                f"version={version}"
            )

        entry["source"] = (
            "langfuse"
        )

        entry["version"] = (
            version
        )

        entry["selector"] = (
            f"label:{label}"
        )

    save_manifest(
        manifest_path,
        manifest,
    )

    print()

    print(
        "Langfuse pull: OK "
        f"(changed={changed})"
    )

    return 0


def push(
    root: Path,
    config: dict[str, str],
) -> int:
    if (
        config.get(
            "LANGFUSE_ENABLED",
            "0",
        )
        != "1"
    ):
        print(
            "Langfuse: disabled; "
            "push skipped"
        )
        return 0

    manifest_path = (
        root
        / ".opencode"
        / "prompt-manifest.json"
    )

    manifest = json.loads(
        manifest_path.read_text(
            encoding="utf-8",
        )
    )

    (
        base_url,
        label,
        credentials,
    ) = langfuse_settings(
        root,
        config,
    )

    pushed = 0
    unchanged = 0

    for (
        kind,
        item_id,
        entry,
        path,
    ) in runtime_items(
        root,
        manifest,
    ):
        name = entry.get(
            "name"
        )

        if not name:
            raise Error(
                "prompt name missing for "
                f"{kind}:{item_id}"
            )

        if not path.is_file():
            raise Error(
                "runtime file not found: "
                f"{path}"
            )

        _, body = split_document(
            path
        )

        (
            created,
            version,
        ) = push_prompt(
            base_url,
            label,
            credentials,
            name,
            body,
        )

        if created:
            pushed += 1

            print(
                f"pushed: "
                f"{kind}:{item_id} "
                f"{name} "
                f"version={version}"
            )

        else:
            unchanged += 1

            print(
                f"unchanged: "
                f"{kind}:{item_id} "
                f"{name} "
                f"version={version}"
            )

        entry["source"] = (
            "langfuse"
        )

        entry["version"] = (
            version
        )

        entry["selector"] = (
            f"label:{label}"
        )

    save_manifest(
        manifest_path,
        manifest,
    )

    print()

    print(
        "Langfuse push: OK "
        f"(pushed={pushed}, "
        f"unchanged={unchanged})"
    )

    return 0


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "command",
        choices=[
            "check",
            "pull",
            "push",
        ],
    )

    parser.add_argument(
        "--root",
        default=".",
    )

    parser.add_argument(
        "--config",
        default="config/tooling.mk",
    )

    args = parser.parse_args()

    root = Path(
        args.root
    ).resolve()

    config_path = Path(
        args.config
    )

    if not config_path.is_absolute():
        config_path = (
            root
            / config_path
        )

    try:
        config = load_config(
            config_path
        )

        if args.command == "check":
            return check(
                root,
                config,
            )

        if args.command == "pull":
            return pull(
                root,
                config,
            )

        if args.command == "push":
            return push(
                root,
                config,
            )

        raise AssertionError(
            args.command
        )

    except (
        Error,
        urllib.error.URLError,
        json.JSONDecodeError,
    ) as exc:
        print(
            f"ERROR: {exc}",
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(main())