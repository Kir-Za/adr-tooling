SHELL := /bin/bash

.DEFAULT_GOAL := help

PROJECT_CONFIG ?= config/project.mk
PROJECT_CONFIG_TEMPLATE ?= config/project.mk.example

LANGFUSE_SECRETS_FILE ?= config/langfuse.secrets.json
LANGFUSE_SECRETS_TEMPLATE ?= config/langfuse.secrets.json.example

# Project configuration is optional while Makefile is being parsed.
# This allows `make help` and `make init-project` on a fresh clone.
-include $(PROJECT_CONFIG)


# -----------------------------------------------------------------------------
# Resolved paths
# -----------------------------------------------------------------------------

ADR_REPO_ABS := $(abspath $(ADR_REPO))

ADR_TEMPLATE_ABS := $(ADR_REPO_ABS)/$(ADR_TEMPLATE)
ADR_APPROVED_ABS := $(ADR_REPO_ABS)/$(ADR_APPROVED)
ADR_PROPOSED_ABS := $(ADR_REPO_ABS)/$(ADR_PROPOSED)
ADR_DIAGRAMS_ABS := $(ADR_REPO_ABS)/$(ADR_DIAGRAMS)


# -----------------------------------------------------------------------------
# Exported render configuration
# -----------------------------------------------------------------------------

export PROJECT_NAME

export ADR_REPO_ABS
export ADR_TEMPLATE_ABS
export ADR_APPROVED_ABS
export ADR_PROPOSED_ABS
export ADR_DIAGRAMS_ABS

export MODEL_ARCHITECT
export MODEL_WRITER
export MODEL_REVIEWER
export MODEL_FINDER
export MODEL_AUDITOR

export AGENT_ARCHITECT
export AGENT_WRITER
export AGENT_REVIEWER
export AGENT_FINDER
export AGENT_AUDITOR

export LANGFUSE_ENABLED
export LANGFUSE_BASE_URL
export LANGFUSE_PROMPT_LABEL

export LANGFUSE_PROMPT_ARCHITECT
export LANGFUSE_PROMPT_WRITER
export LANGFUSE_PROMPT_REVIEWER
export LANGFUSE_PROMPT_FINDER
export LANGFUSE_PROMPT_AUDITOR

export LANGFUSE_VERSION_ARCHITECT
export LANGFUSE_VERSION_WRITER
export LANGFUSE_VERSION_REVIEWER
export LANGFUSE_VERSION_FINDER
export LANGFUSE_VERSION_AUDITOR


# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

.PHONY: help
help:
	@echo "ADR Tooling"
	@echo
	@echo "Setup:"
	@echo "  make init-project    Create local project configuration"
	@echo "  make bootstrap       Validate project and render OpenCode runtime"
	@echo
	@echo "Validation:"
	@echo "  make config          Show resolved project configuration"
	@echo "  make check           Validate project environment"
	@echo "  make check-models    Validate required OpenCode models"
	@echo "  make ci-check        Run project validation and render checks"
	@echo
	@echo "Rendering:"
	@echo "  make render          Generate OpenCode runtime files"
	@echo "  make render-check    Verify generated files are up to date"
	@echo
	@echo "Langfuse:"
	@echo "  make langfuse-check  Validate Langfuse configuration and connectivity"
	@echo "  make prompts-push    Publish Git-default prompt bodies to Langfuse"


# -----------------------------------------------------------------------------
# Local project initialization
# -----------------------------------------------------------------------------

.PHONY: init-project
init-project:
	@test -f "$(PROJECT_CONFIG_TEMPLATE)" || { \
		echo "ERROR: project config template not found: $(PROJECT_CONFIG_TEMPLATE)"; \
		exit 1; \
	}
	@if [ -f "$(PROJECT_CONFIG)" ]; then \
		echo "$(PROJECT_CONFIG) already exists"; \
	else \
		cp "$(PROJECT_CONFIG_TEMPLATE)" "$(PROJECT_CONFIG)"; \
		echo "created: $(PROJECT_CONFIG)"; \
	fi
	@$(MAKE) --no-print-directory init-langfuse-secrets


.PHONY: init-langfuse-secrets
init-langfuse-secrets:
	@if [ "$(LANGFUSE_ENABLED)" = "1" ]; then \
		test -f "$(LANGFUSE_SECRETS_TEMPLATE)" || { \
			echo "ERROR: Langfuse secrets template not found: $(LANGFUSE_SECRETS_TEMPLATE)"; \
			exit 1; \
		}; \
		if [ -f "$(LANGFUSE_SECRETS_FILE)" ]; then \
			echo "$(LANGFUSE_SECRETS_FILE) already exists"; \
		else \
			cp "$(LANGFUSE_SECRETS_TEMPLATE)" "$(LANGFUSE_SECRETS_FILE)"; \
			chmod 600 "$(LANGFUSE_SECRETS_FILE)"; \
			echo "created: $(LANGFUSE_SECRETS_FILE)"; \
			echo "configure Langfuse credentials in $(LANGFUSE_SECRETS_FILE)"; \
		fi; \
	fi


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

.PHONY: config
config: check-config
	@echo "PROJECT_NAME=$(PROJECT_NAME)"
	@echo "ADR_REPO=$(ADR_REPO_ABS)"
	@echo "ADR_TEMPLATE=$(ADR_TEMPLATE_ABS)"
	@echo "ADR_APPROVED=$(ADR_APPROVED_ABS)"
	@echo "ADR_PROPOSED=$(ADR_PROPOSED_ABS)"
	@echo "ADR_DIAGRAMS=$(ADR_DIAGRAMS_ABS)"
	@echo
	@echo "MODEL_ARCHITECT=$(MODEL_ARCHITECT)"
	@echo "MODEL_WRITER=$(MODEL_WRITER)"
	@echo "MODEL_REVIEWER=$(MODEL_REVIEWER)"
	@echo "MODEL_FINDER=$(MODEL_FINDER)"
	@echo "MODEL_AUDITOR=$(MODEL_AUDITOR)"
	@echo
	@echo "LANGFUSE_ENABLED=$(LANGFUSE_ENABLED)"
	@echo "LANGFUSE_BASE_URL=$(LANGFUSE_BASE_URL)"
	@echo "LANGFUSE_PROMPT_LABEL=$(LANGFUSE_PROMPT_LABEL)"
	@echo "LANGFUSE_SECRETS_FILE=$(LANGFUSE_SECRETS_FILE)"


# -----------------------------------------------------------------------------
# Project configuration validation
# -----------------------------------------------------------------------------

.PHONY: check-config
check-config:
	@test -f "$(PROJECT_CONFIG)" || { \
		echo "ERROR: project config not found: $(PROJECT_CONFIG)"; \
		echo "Run: make init-project"; \
		exit 1; \
	}
	@test -n "$(PROJECT_NAME)" || { \
		echo "ERROR: PROJECT_NAME is not configured"; \
		exit 1; \
	}
	@test -n "$(ADR_REPO)" || { \
		echo "ERROR: ADR_REPO is not configured"; \
		exit 1; \
	}
	@test -n "$(ADR_TEMPLATE)" || { \
		echo "ERROR: ADR_TEMPLATE is not configured"; \
		exit 1; \
	}
	@test -n "$(ADR_APPROVED)" || { \
		echo "ERROR: ADR_APPROVED is not configured"; \
		exit 1; \
	}
	@test -n "$(ADR_PROPOSED)" || { \
		echo "ERROR: ADR_PROPOSED is not configured"; \
		exit 1; \
	}
	@test -n "$(ADR_DIAGRAMS)" || { \
		echo "ERROR: ADR_DIAGRAMS is not configured"; \
		exit 1; \
	}
	@test -n "$(MODEL_ARCHITECT)" || { \
		echo "ERROR: MODEL_ARCHITECT is not configured"; \
		exit 1; \
	}
	@test -n "$(MODEL_WRITER)" || { \
		echo "ERROR: MODEL_WRITER is not configured"; \
		exit 1; \
	}
	@test -n "$(MODEL_REVIEWER)" || { \
		echo "ERROR: MODEL_REVIEWER is not configured"; \
		exit 1; \
	}
	@test -n "$(MODEL_FINDER)" || { \
		echo "ERROR: MODEL_FINDER is not configured"; \
		exit 1; \
	}
	@test -n "$(MODEL_AUDITOR)" || { \
		echo "ERROR: MODEL_AUDITOR is not configured"; \
		exit 1; \
	}
	@test -n "$(AGENT_ARCHITECT)" || { \
		echo "ERROR: AGENT_ARCHITECT is not configured"; \
		exit 1; \
	}
	@test -n "$(AGENT_WRITER)" || { \
		echo "ERROR: AGENT_WRITER is not configured"; \
		exit 1; \
	}
	@test -n "$(AGENT_REVIEWER)" || { \
		echo "ERROR: AGENT_REVIEWER is not configured"; \
		exit 1; \
	}
	@test -n "$(AGENT_FINDER)" || { \
		echo "ERROR: AGENT_FINDER is not configured"; \
		exit 1; \
	}
	@test -n "$(AGENT_AUDITOR)" || { \
		echo "ERROR: AGENT_AUDITOR is not configured"; \
		exit 1; \
	}
	@echo "config: OK"


# -----------------------------------------------------------------------------
# Environment validation
# -----------------------------------------------------------------------------

.PHONY: check
check: check-config check-tools check-repository check-resources
	@echo
	@echo "Environment: OK"


.PHONY: check-tools
check-tools:
	@command -v opencode >/dev/null || { \
		echo "ERROR: opencode not found"; \
		exit 1; \
	}
	@command -v git >/dev/null || { \
		echo "ERROR: git not found"; \
		exit 1; \
	}
	@command -v python3 >/dev/null || { \
		echo "ERROR: python3 not found"; \
		exit 1; \
	}
	@echo "tools: OK"


.PHONY: check-repository
check-repository: check-config
	@test -d "$(ADR_REPO_ABS)" || { \
		echo "ERROR: ADR repository not found: $(ADR_REPO_ABS)"; \
		exit 1; \
	}
	@git -C "$(ADR_REPO_ABS)" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { \
		echo "ERROR: ADR repository is not a Git repository"; \
		exit 1; \
	}
	@echo "repository: OK"


.PHONY: check-resources
check-resources: check-config
	@test -f "$(ADR_TEMPLATE_ABS)" || { \
		echo "ERROR: ADR template not found: $(ADR_TEMPLATE_ABS)"; \
		exit 1; \
	}
	@test -d "$(ADR_APPROVED_ABS)" || { \
		echo "ERROR: approved ADR directory not found: $(ADR_APPROVED_ABS)"; \
		exit 1; \
	}
	@test -d "$(ADR_PROPOSED_ABS)" || { \
		echo "ERROR: proposed ADR directory not found: $(ADR_PROPOSED_ABS)"; \
		exit 1; \
	}
	@test -d "$(ADR_DIAGRAMS_ABS)" || { \
		echo "ERROR: diagrams directory not found: $(ADR_DIAGRAMS_ABS)"; \
		exit 1; \
	}
	@echo "resources: OK"


# -----------------------------------------------------------------------------
# Model validation
# -----------------------------------------------------------------------------

.PHONY: check-models
check-models: check-config
	@AVAILABLE_MODELS="$$(opencode models)"; \
	for MODEL in \
		"$(MODEL_ARCHITECT)" \
		"$(MODEL_WRITER)" \
		"$(MODEL_REVIEWER)" \
		"$(MODEL_FINDER)" \
		"$(MODEL_AUDITOR)"; \
	do \
		echo "$$AVAILABLE_MODELS" | grep -Fx "$$MODEL" >/dev/null || { \
			echo "ERROR: model not available: $$MODEL"; \
			exit 1; \
		}; \
	done
	@echo "models: OK"


# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

.PHONY: render
render: check-config render-opencode render-agents render-commands render-plugins
	@echo
	@echo "Render: OK"


.PHONY: render-check
render-check: \
	check-config \
	render-check-opencode \
	render-check-agents \
	render-check-commands \
	render-check-plugins
	@echo
	@echo "Render check: OK"


.PHONY: render-opencode
render-opencode:
	@python3 scripts/render.py \
		render \
		templates/opencode.json.tpl \
		opencode.json


.PHONY: render-check-opencode
render-check-opencode:
	@python3 scripts/render.py \
		check \
		templates/opencode.json.tpl \
		opencode.json


.PHONY: render-agents
render-agents:
	@python3 scripts/render.py \
		render \
		templates/AGENTS.md.tpl \
		AGENTS.md

	@python3 scripts/render_agent.py render \
		--template templates/agents/architecture-finder.md.tpl \
		--output .opencode/agents/architecture-finder.md \
		--prompt-name "$(LANGFUSE_PROMPT_FINDER)" \
		--prompt-version "$(LANGFUSE_VERSION_FINDER)"

	@python3 scripts/render_agent.py render \
		--template templates/agents/architect.md.tpl \
		--output .opencode/agents/architect.md \
		--prompt-name "$(LANGFUSE_PROMPT_ARCHITECT)" \
		--prompt-version "$(LANGFUSE_VERSION_ARCHITECT)"

	@python3 scripts/render_agent.py render \
		--template templates/agents/adr-writer.md.tpl \
		--output .opencode/agents/adr-writer.md \
		--prompt-name "$(LANGFUSE_PROMPT_WRITER)" \
		--prompt-version "$(LANGFUSE_VERSION_WRITER)"

	@python3 scripts/render_agent.py render \
		--template templates/agents/adr-reviewer.md.tpl \
		--output .opencode/agents/adr-reviewer.md \
		--prompt-name "$(LANGFUSE_PROMPT_REVIEWER)" \
		--prompt-version "$(LANGFUSE_VERSION_REVIEWER)"

	@python3 scripts/render_agent.py render \
		--template templates/agents/consistency-auditor.md.tpl \
		--output .opencode/agents/consistency-auditor.md \
		--prompt-name "$(LANGFUSE_PROMPT_AUDITOR)" \
		--prompt-version "$(LANGFUSE_VERSION_AUDITOR)"


.PHONY: render-check-agents
render-check-agents:
	@python3 scripts/render.py \
		check \
		templates/AGENTS.md.tpl \
		AGENTS.md

	@python3 scripts/render_agent.py check \
		--template templates/agents/architecture-finder.md.tpl \
		--output .opencode/agents/architecture-finder.md \
		--prompt-name "$(LANGFUSE_PROMPT_FINDER)" \
		--prompt-version "$(LANGFUSE_VERSION_FINDER)"

	@python3 scripts/render_agent.py check \
		--template templates/agents/architect.md.tpl \
		--output .opencode/agents/architect.md \
		--prompt-name "$(LANGFUSE_PROMPT_ARCHITECT)" \
		--prompt-version "$(LANGFUSE_VERSION_ARCHITECT)"

	@python3 scripts/render_agent.py check \
		--template templates/agents/adr-writer.md.tpl \
		--output .opencode/agents/adr-writer.md \
		--prompt-name "$(LANGFUSE_PROMPT_WRITER)" \
		--prompt-version "$(LANGFUSE_VERSION_WRITER)"

	@python3 scripts/render_agent.py check \
		--template templates/agents/adr-reviewer.md.tpl \
		--output .opencode/agents/adr-reviewer.md \
		--prompt-name "$(LANGFUSE_PROMPT_REVIEWER)" \
		--prompt-version "$(LANGFUSE_VERSION_REVIEWER)"

	@python3 scripts/render_agent.py check \
		--template templates/agents/consistency-auditor.md.tpl \
		--output .opencode/agents/consistency-auditor.md \
		--prompt-name "$(LANGFUSE_PROMPT_AUDITOR)" \
		--prompt-version "$(LANGFUSE_VERSION_AUDITOR)"


.PHONY: render-commands
render-commands:
	@python3 scripts/render.py render \
		templates/commands/architect.md.tpl \
		.opencode/commands/architect.md
	@python3 scripts/render.py render \
		templates/commands/write-adr.md.tpl \
		.opencode/commands/write-adr.md
	@python3 scripts/render.py render \
		templates/commands/review-adr.md.tpl \
		.opencode/commands/review-adr.md
	@python3 scripts/render.py render \
		templates/commands/find-architecture.md.tpl \
		.opencode/commands/find-architecture.md
	@python3 scripts/render.py render \
		templates/commands/audit-consistency.md.tpl \
		.opencode/commands/audit-consistency.md


.PHONY: render-check-commands
render-check-commands:
	@python3 scripts/render.py check \
		templates/commands/architect.md.tpl \
		.opencode/commands/architect.md
	@python3 scripts/render.py check \
		templates/commands/write-adr.md.tpl \
		.opencode/commands/write-adr.md
	@python3 scripts/render.py check \
		templates/commands/review-adr.md.tpl \
		.opencode/commands/review-adr.md
	@python3 scripts/render.py check \
		templates/commands/find-architecture.md.tpl \
		.opencode/commands/find-architecture.md
	@python3 scripts/render.py check \
		templates/commands/audit-consistency.md.tpl \
		.opencode/commands/audit-consistency.md


.PHONY: render-plugins
render-plugins:
	@python3 scripts/render.py render \
		templates/plugins/langfuse.ts.tpl \
		.opencode/plugins/langfuse.ts


.PHONY: render-check-plugins
render-check-plugins:
	@python3 scripts/render.py check \
		templates/plugins/langfuse.ts.tpl \
		.opencode/plugins/langfuse.ts


# -----------------------------------------------------------------------------
# CI
# -----------------------------------------------------------------------------

.PHONY: ci-check
ci-check: check check-models render-check
	@echo
	@echo "CI check: OK"


# -----------------------------------------------------------------------------
# Bootstrap
# -----------------------------------------------------------------------------

.PHONY: bootstrap
bootstrap:
	@echo "Bootstrapping ADR tooling..."
	@echo
	@$(MAKE) --no-print-directory check
	@$(MAKE) --no-print-directory check-models
	@$(MAKE) --no-print-directory init-langfuse-secrets
	@$(MAKE) --no-print-directory render
	@$(MAKE) --no-print-directory render-check
	@echo
	@echo "Bootstrap: OK"
	@echo
	@echo "Project: $(PROJECT_NAME)"
	@echo "ADR repository: $(ADR_REPO_ABS)"


# -----------------------------------------------------------------------------
# Optional Langfuse integration
# -----------------------------------------------------------------------------

.PHONY: langfuse-check-config
langfuse-check-config: check-config
	@test "$(LANGFUSE_ENABLED)" = "1" || { \
		echo "ERROR: Langfuse integration is disabled"; \
		exit 1; \
	}
	@test -n "$(LANGFUSE_BASE_URL)" || { \
		echo "ERROR: LANGFUSE_BASE_URL is not configured"; \
		exit 1; \
	}
	@test -n "$(LANGFUSE_PROMPT_LABEL)" || { \
		echo "ERROR: LANGFUSE_PROMPT_LABEL is not configured"; \
		exit 1; \
	}
	@echo "langfuse config: OK"


.PHONY: langfuse-check-auth
langfuse-check-auth:
	@test -f "$(LANGFUSE_SECRETS_FILE)" || { \
		echo "ERROR: Langfuse secrets file not found: $(LANGFUSE_SECRETS_FILE)"; \
		echo "Run: make init-project"; \
		exit 1; \
	}
	@python3 -c 'import json; p="$(LANGFUSE_SECRETS_FILE)"; d=json.load(open(p)); assert isinstance(d.get("public_key"), str) and d["public_key"], "public_key is missing"; assert isinstance(d.get("secret_key"), str) and d["secret_key"], "secret_key is missing"' || { \
		echo "ERROR: invalid Langfuse secrets file: $(LANGFUSE_SECRETS_FILE)"; \
		exit 1; \
	}
	@echo "langfuse auth: PRESENT"


.PHONY: langfuse-check-health
langfuse-check-health: langfuse-check-config
	@command -v curl >/dev/null || { \
		echo "ERROR: curl not found"; \
		exit 1; \
	}
	@curl --fail --silent --show-error \
		"$(LANGFUSE_BASE_URL)/api/public/health?failIfDatabaseUnavailable=true" \
		>/dev/null || { \
			echo "ERROR: Langfuse is unavailable: $(LANGFUSE_BASE_URL)"; \
			exit 1; \
	}
	@echo "langfuse health: OK"


.PHONY: langfuse-check-api
langfuse-check-api: langfuse-check-config langfuse-check-auth
	@command -v curl >/dev/null || { \
		echo "ERROR: curl not found"; \
		exit 1; \
	}
	@set -euo pipefail; \
	readarray -t LANGFUSE_CREDS < <( \
		python3 -c 'import json; d=json.load(open("$(LANGFUSE_SECRETS_FILE)")); print(d["public_key"]); print(d["secret_key"])' \
	); \
	curl --fail --silent --show-error \
		-u "$${LANGFUSE_CREDS[0]}:$${LANGFUSE_CREDS[1]}" \
		"$(LANGFUSE_BASE_URL)/api/public/projects" \
		>/dev/null || { \
			echo "ERROR: Langfuse API authentication failed"; \
			exit 1; \
		}
	@echo "langfuse api: OK"


.PHONY: langfuse-check
langfuse-check: \
	langfuse-check-config \
	langfuse-check-auth \
	langfuse-check-health \
	langfuse-check-api
	@echo
	@echo "Langfuse: OK"


# -----------------------------------------------------------------------------
# Langfuse Prompt Registry
# -----------------------------------------------------------------------------

.PHONY: prompts-push
prompts-push: langfuse-check
	@python3 scripts/langfuse_prompt.py \
		--name "$(LANGFUSE_PROMPT_ARCHITECT)" \
		--label "$(LANGFUSE_PROMPT_LABEL)" \
		--template templates/agents/architect.md.tpl
	@python3 scripts/langfuse_prompt.py \
		--name "$(LANGFUSE_PROMPT_WRITER)" \
		--label "$(LANGFUSE_PROMPT_LABEL)" \
		--template templates/agents/adr-writer.md.tpl
	@python3 scripts/langfuse_prompt.py \
		--name "$(LANGFUSE_PROMPT_REVIEWER)" \
		--label "$(LANGFUSE_PROMPT_LABEL)" \
		--template templates/agents/adr-reviewer.md.tpl
	@python3 scripts/langfuse_prompt.py \
		--name "$(LANGFUSE_PROMPT_FINDER)" \
		--label "$(LANGFUSE_PROMPT_LABEL)" \
		--template templates/agents/architecture-finder.md.tpl
	@python3 scripts/langfuse_prompt.py \
		--name "$(LANGFUSE_PROMPT_AUDITOR)" \
		--label "$(LANGFUSE_PROMPT_LABEL)" \
		--template templates/agents/consistency-auditor.md.tpl
	@echo
	@echo "Langfuse prompts push: OK"