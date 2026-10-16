{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "external_directory": {
      "${ADR_REPO_ABS}/**": "allow"
    },
    "read": "allow",
    "edit": {
      "*": "ask",
      "${ADR_REPO_ABS}/**": "deny",
      "${ADR_PROPOSED_ABS}/**": "allow"
    },
    "bash": "deny",
    "webfetch": "deny",
    "websearch": "deny"
  }
}