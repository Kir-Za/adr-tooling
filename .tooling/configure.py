#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


class Error(RuntimeError):
    pass


AGENT_MODEL_KEYS = {
    "architect":
        "MODEL_ARCHITECT",

    "adr-writer":
        "MODEL_WRITER",

    "adr-reviewer":
        "MODEL_REVIEWER",

    "architecture-finder":
        "MODEL_FINDER",

    "consistency-auditor":
        "MODEL_AUDITOR",
}


def fail(
    message: str,
) -> None:
    raise Error(
        message
    )


def load_make_config(
    path: Path,
) -> dict[str, str]:
    if not path.is_file():
        fail(
            f"config not found: {path}"
        )

    result: dict[str, str] = {}

    for raw in path.read_text(
        encoding="utf-8",
    ).splitlines():
        line = raw.strip()

        if (
            not line
            or line.startswith("#")
        ):
            continue

        if "?=" in line:
            key, value = line.split("?=", 1)

        elif ":=" in line:
            key, value = (
                line.split(
                    ":=",
                    1,
                )
            )

        elif "=" in line:
            key, value = (
                line.split(
                    "=",
                    1,
                )
            )

        else:
            continue

        result[
            key.strip()
        ] = value.strip()

    return result


def required(
    config: dict[str, str],
    key: str,
) -> str:
    value = config.get(
        key,
        "",
    ).strip()

    if not value:
        fail(
            f"{key} is not configured"
        )

    return value


def resolve_path(
    repo: Path,
    value: str,
) -> Path:
    path = Path(
        value
    ).expanduser()

    if not path.is_absolute():
        path = (
            repo
            / path
        )

    return path.resolve()


def desired_state(
    config: dict[str, str],
    root: Path,
    adr_repo_override: str | None = None,
) -> dict:
    repo = resolve_path(
        root,
        adr_repo_override
        or required(config, "ADR_REPO"),
    )

    paths = {
        "repo":
            repo,

        "template":
            resolve_path(
                repo,
                required(
                    config,
                    "ADR_TEMPLATE",
                ),
            ),

        "approved":
            resolve_path(
                repo,
                required(
                    config,
                    "ADR_APPROVED",
                ),
            ),

        "proposed":
            resolve_path(
                repo,
                required(
                    config,
                    "ADR_PROPOSED",
                ),
            ),

        "diagrams":
            resolve_path(
                repo,
                required(
                    config,
                    "ADR_DIAGRAMS",
                ),
            ),
    }

    models = {
        agent:
            required(
                config,
                config_key,
            )
        for agent, config_key
        in AGENT_MODEL_KEYS.items()
    }

    return {
        "paths":
            paths,
        "models":
            models,
    }


def validate_source_paths(
    state: dict,
) -> None:
    paths = state[
        "paths"
    ]

    if not paths[
        "repo"
    ].is_dir():
        fail(
            "ADR_REPO does not exist: "
            f"{paths['repo']}"
        )

    if not paths[
        "template"
    ].is_file():
        fail(
            "ADR_TEMPLATE does not exist: "
            f"{paths['template']}"
        )

    for key in (
        "approved",
        "proposed",
        "diagrams",
    ):
        if not paths[
            key
        ].is_dir():
            fail(
                f"ADR_{key.upper()} "
                "does not exist: "
                f"{paths[key]}"
            )


def configure_agents(
    root: Path,
    new_state: dict,
) -> None:
    templates = (
        root
        / ".tooling"
        / "agent-templates"
    )
    directory = root / ".opencode" / "agents"

    if not templates.is_dir():
        fail(
            "agent templates directory not found: "
            f"{templates}"
        )
    directory.mkdir(parents=True, exist_ok=True)

    for agent, model in (
        new_state[
            "models"
        ].items()
    ):
        template_path = (
            templates
            / f"{agent}.md"
        )
        path = directory / f"{agent}.md"

        if not template_path.is_file():
            fail(
                "agent template not found: "
                f"{template_path}"
            )

        text = template_path.read_text(
            encoding="utf-8",
        )
        paths = new_state["paths"]
        text = text.replace(
            "{{ADR_REPO_GLOB}}",
            json.dumps(
                f"{paths['repo']}/*",
                ensure_ascii=False,
            ),
        ).replace(
            "{{ADR_PROPOSED_GLOB}}",
            json.dumps(
                f"{paths['proposed']}/*",
                ensure_ascii=False,
            ),
        )

        lines = text.splitlines()
        for index, line in enumerate(lines):
            if line.startswith("model:"):
                lines[index] = f"model: {model}"
                break
        else:
            fail(f"model not configured in {path}")
        text = "\n".join(lines) + "\n"

        path.write_text(
            text,
            encoding="utf-8",
        )

        print(
            f"configured: {path}"
        )


def configure_opencode(
    root: Path,
    state: dict,
) -> None:
    path = root / "opencode.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        relative_repo = os.path.relpath(
            state["paths"]["repo"],
            root,
        )
        data["references"]["architecture"]["path"] = relative_repo
        data["mcp"]["servers"]["openflowkit"]["cwd"] = relative_repo
    except (
        FileNotFoundError,
        json.JSONDecodeError,
        KeyError,
        TypeError,
    ) as exc:
        fail(f"cannot configure opencode.json: {exc}")

    path.write_text(
        json.dumps(data, indent=2) + "\n",
        encoding="utf-8",
    )


def current_model(
    path: Path,
) -> str | None:
    for line in path.read_text(
        encoding="utf-8",
    ).splitlines():
        if line.startswith(
            "model:"
        ):
            return (
                line.split(
                    ":",
                    1,
                )[1]
                .strip()
            )

    return None


def check_runtime(
    root: Path,
    desired: dict,
) -> None:
    desired_paths = desired[
        "paths"
    ]

    try:
        opencode = json.loads(
            (
                root
                / "opencode.json"
            ).read_text(
                encoding="utf-8",
            )
        )

        reference = resolve_path(
            root,
            opencode[
                "references"
            ][
                "architecture"
            ][
                "path"
            ]
        )

        mcp_cwd = resolve_path(
            root,
            opencode[
                "mcp"
            ][
                "servers"
            ][
                "openflowkit"
            ][
                "cwd"
            ]
        )

    except (
        FileNotFoundError,
        json.JSONDecodeError,
        KeyError,
        TypeError,
    ) as exc:
        fail(
            "cannot validate "
            f"opencode.json: {exc}"
        )

    if reference != desired_paths[
        "repo"
    ]:
        fail(
            "architecture reference "
            "does not match config"
        )

    if mcp_cwd != desired_paths[
        "repo"
    ]:
        fail(
            "OpenFlowKit cwd "
            "does not match config"
        )

    agents = (
        root
        / ".opencode"
        / "agents"
    )

    for agent, expected_model in (
        desired[
            "models"
        ].items()
    ):
        path = (
            agents
            / f"{agent}.md"
        )

        actual = current_model(
            path
        )

        if actual != expected_model:
            fail(
                f"{agent} model "
                "does not match config: "
                f"{actual}"
            )

        text = path.read_text(
            encoding="utf-8",
        )

        if "{{ADR_" in text:
            fail(
                "unresolved ADR "
                f"placeholder in {path}"
            )

        if json.dumps(
            f"{desired_paths['repo']}/*",
            ensure_ascii=False,
        ) not in text:
            fail(
                f"{agent} repository permissions "
                "do not match ADR_REPO"
            )

        if agent == "adr-writer" and json.dumps(
            f"{desired_paths['proposed']}/*",
            ensure_ascii=False,
        ) not in text:
            fail(
                "adr-writer edit permission "
                "does not match ADR_PROPOSED"
            )

        if "${MODEL_" in text:
            fail(
                "unresolved model "
                f"placeholder in {path}"
            )


def print_state(
    state: dict,
) -> None:
    paths = state[
        "paths"
    ]

    print(
        f"ADR_REPO: "
        f"{paths['repo']}"
    )

    print(
        f"ADR_TEMPLATE: "
        f"{paths['template']}"
    )

    print(
        f"ADR_APPROVED: "
        f"{paths['approved']}"
    )

    print(
        f"ADR_PROPOSED: "
        f"{paths['proposed']}"
    )

    print(
        f"ADR_DIAGRAMS: "
        f"{paths['diagrams']}"
    )

    print()

    for agent, model in sorted(
        state[
            "models"
        ].items()
    ):
        print(
            f"{agent}: {model}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--root",
        default=".",
    )

    parser.add_argument(
        "--config",
        default="config/tooling.mk",
    )
    parser.add_argument(
        "--adr-repo",
        help="Override ADR_REPO from the Make configuration",
    )

    parser.add_argument(
        "--check",
        action="store_true",
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
        config = load_make_config(
            config_path
        )

        desired = desired_state(
            config,
            root,
            args.adr_repo,
        )

        validate_source_paths(
            desired
        )

        if args.check:
            check_runtime(
                root,
                desired,
            )

            print(
                "Tooling configuration: OK"
            )

            print_state(
                desired
            )

            return 0

        configure_opencode(
            root,
            desired,
        )

        configure_agents(
            root,
            desired,
        )

        check_runtime(
            root,
            desired,
        )

        print()
        print(
            "Tooling configured: OK"
        )

        print_state(
            desired
        )

        return 0

    except Error as exc:
        print(
            f"ERROR: {exc}",
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
