#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
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

        if ":=" in line:
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
) -> dict:
    repo = Path(
        required(
            config,
            "ADR_REPO",
        )
    ).expanduser().resolve()

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


def load_runtime_state(
    path: Path,
) -> dict:
    if not path.is_file():
        fail(
            "runtime state not found: "
            f"{path}"
        )

    try:
        raw = json.loads(
            path.read_text(
                encoding="utf-8",
            )
        )
    except json.JSONDecodeError as exc:
        fail(
            "invalid runtime state: "
            f"{exc}"
        )

    if not isinstance(
        raw.get("paths"),
        dict,
    ):
        fail(
            "runtime state has "
            "no paths"
        )

    if not isinstance(
        raw.get("models"),
        dict,
    ):
        fail(
            "runtime state has "
            "no models"
        )

    return {
        "paths": {
            key:
                Path(
                    value
                ).resolve()
            for key, value
            in raw[
                "paths"
            ].items()
        },
        "models":
            dict(
                raw[
                    "models"
                ]
            ),
    }


def save_runtime_state(
    path: Path,
    state: dict,
) -> None:
    data = {
        "paths": {
            key:
                str(value)
            for key, value
            in state[
                "paths"
            ].items()
        },
        "models":
            state[
                "models"
            ],
    }

    path.write_text(
        json.dumps(
            data,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def configure_opencode(
    root: Path,
    desired: dict,
) -> None:
    path = (
        root
        / "opencode.json"
    )

    try:
        data = json.loads(
            path.read_text(
                encoding="utf-8",
            )
        )

        data[
            "references"
        ][
            "architecture"
        ][
            "path"
        ] = str(
            desired[
                "paths"
            ][
                "repo"
            ]
        )

        data[
            "mcp"
        ][
            "servers"
        ][
            "openflowkit"
        ][
            "cwd"
        ] = str(
            desired[
                "paths"
            ][
                "repo"
            ]
        )

    except (
        FileNotFoundError,
        json.JSONDecodeError,
        KeyError,
        TypeError,
    ) as exc:
        fail(
            "cannot configure "
            f"opencode.json: {exc}"
        )

    path.write_text(
        json.dumps(
            data,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def replace_old_paths(
    text: str,
    old: dict[str, Path],
    new: dict[str, Path],
) -> str:
    pairs = sorted(
        (
            (
                str(
                    old[key]
                ),
                str(
                    new[key]
                ),
            )
            for key in old
            if key in new
        ),
        key=lambda item:
            len(
                item[0]
            ),
        reverse=True,
    )

    result = text

    for before, after in pairs:
        result = (
            result.replace(
                before,
                after,
            )
        )

    return result


def configure_agents(
    root: Path,
    old_state: dict,
    new_state: dict,
) -> None:
    directory = (
        root
        / ".opencode"
        / "agents"
    )

    if not directory.is_dir():
        fail(
            "agents directory not found: "
            f"{directory}"
        )

    for agent, model in (
        new_state[
            "models"
        ].items()
    ):
        path = (
            directory
            / f"{agent}.md"
        )

        if not path.is_file():
            fail(
                "agent file not found: "
                f"{path}"
            )

        text = path.read_text(
            encoding="utf-8",
        )

        text = replace_old_paths(
            text,
            old_state[
                "paths"
            ],
            new_state[
                "paths"
            ],
        )

        old_model = (
            old_state[
                "models"
            ].get(
                agent
            )
        )

        if old_model:
            text = text.replace(
                f"model: {old_model}",
                f"model: {model}",
                1,
            )

        path.write_text(
            text,
            encoding="utf-8",
        )

        print(
            f"configured: {path}"
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
    state_path: Path,
) -> None:
    state = load_runtime_state(
        state_path
    )

    desired_paths = desired[
        "paths"
    ]

    if state[
        "paths"
    ] != desired_paths:
        fail(
            "runtime paths differ "
            "from config; run "
            "make configure"
        )

    if state[
        "models"
    ] != desired[
        "models"
    ]:
        fail(
            "runtime models differ "
            "from config; run "
            "make configure"
        )

    try:
        opencode = json.loads(
            (
                root
                / "opencode.json"
            ).read_text(
                encoding="utf-8",
            )
        )

        reference = Path(
            opencode[
                "references"
            ][
                "architecture"
            ][
                "path"
            ]
        ).resolve()

        mcp_cwd = Path(
            opencode[
                "mcp"
            ][
                "servers"
            ][
                "openflowkit"
            ][
                "cwd"
            ]
        ).resolve()

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

        if "${ADR_" in text:
            fail(
                "unresolved ADR "
                f"placeholder in {path}"
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

    state_path = (
        root
        / ".tooling"
        / "runtime-state.json"
    )

    try:
        config = load_make_config(
            config_path
        )

        desired = desired_state(
            config
        )

        validate_source_paths(
            desired
        )

        if args.check:
            check_runtime(
                root,
                desired,
                state_path,
            )

            print(
                "Tooling configuration: OK"
            )

            print_state(
                desired
            )

            return 0

        old_state = load_runtime_state(
            state_path
        )

        configure_opencode(
            root,
            desired,
        )

        configure_agents(
            root,
            old_state,
            desired,
        )

        save_runtime_state(
            state_path,
            desired,
        )

        check_runtime(
            root,
            desired,
            state_path,
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