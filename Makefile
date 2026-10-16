SHELL := /bin/bash

.DEFAULT_GOAL := help

PROJECT_CONFIG ?= config/project.mk

ifeq ($(wildcard $(PROJECT_CONFIG)),)
$(error Project config not found: $(PROJECT_CONFIG))
endif

include $(PROJECT_CONFIG)


# -----------------------------------------------------------------------------
# Resolved paths
# -----------------------------------------------------------------------------

ADR_REPO_ABS := $(abspath $(ADR_REPO))

ADR_TEMPLATE_ABS := $(ADR_REPO_ABS)/$(ADR_TEMPLATE)
ADR_APPROVED_ABS := $(ADR_REPO_ABS)/$(ADR_APPROVED)
ADR_PROPOSED_ABS := $(ADR_REPO_ABS)/$(ADR_PROPOSED)
ADR_DIAGRAMS_ABS := $(ADR_REPO_ABS)/$(ADR_DIAGRAMS)

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


# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

.PHONY: help
help:
	@echo "ADR Tooling"
	@echo
	@echo "Project:"
	@echo "  PROJECT_NAME      $(PROJECT_NAME)"
	@echo "  ADR_REPO          $(ADR_REPO_ABS)"
	@echo
	@echo "Commands:"
	@echo "  make config         Show resolved project configuration"
	@echo "  make check         Validate project environment"
	@echo "  make check-models  Validate required OpenAI models"
	@echo "  make architect     Run principal architect (PROMPT=...)"
	@echo "  make find           Run architecture finder (PROMPT=...)"
	@echo "  make write-adr     Run ADR writer (PROMPT=...)"
	@echo "  make review-adr    Review proposed ADR (ADR=...)"
	@echo "  make audit         Audit architecture consistency"
	@echo "  make ci-check      Run all non-mutating CI checks"
	@echo "  make bootstrap     Validate environment and generate OpenCode configuration"


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

.PHONY: config
config:
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


# -----------------------------------------------------------------------------
# Validation
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
check-repository:
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
check-resources:
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
check-models:
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
# Runtime roles
# -----------------------------------------------------------------------------

.PHONY: architect
architect:
	@test -n "$(PROMPT)" || { \
		echo 'ERROR: PROMPT is required'; \
		echo 'Usage: make architect PROMPT="..."'; \
		exit 1; \
	}
	@opencode run \
		--agent "$(AGENT_ARCHITECT)" \
		--model "$(MODEL_ARCHITECT)" \
		"$(PROMPT)"


.PHONY: find
find:
	@test -n "$(PROMPT)" || { \
		echo 'ERROR: PROMPT is required'; \
		echo 'Usage: make find PROMPT="..."'; \
		exit 1; \
	}
	@opencode run \
		--agent "$(AGENT_FINDER)" \
		--model "$(MODEL_FINDER)" \
		"$(PROMPT)"


.PHONY: write-adr
write-adr:
	@test -n "$(PROMPT)" || { \
		echo 'ERROR: PROMPT is required'; \
		echo 'Usage: make write-adr PROMPT="..."'; \
		exit 1; \
	}
	@opencode run \
		--agent "$(AGENT_WRITER)" \
		--model "$(MODEL_WRITER)" \
		"$(PROMPT)"


.PHONY: review-adr
review-adr:
	@test -n "$(ADR)" || { \
		echo 'ERROR: ADR is required'; \
		echo 'Usage: make review-adr ADR=chunking.md'; \
		exit 1; \
	}
	@opencode run \
		--agent "$(AGENT_REVIEWER)" \
		--model "$(MODEL_REVIEWER)" \
		"Review $(ADR_PROPOSED_ABS)/$(ADR) against the canonical template and relevant approved ADRs. Do not modify files."


.PHONY: audit
audit:
	@opencode run \
		--agent "$(AGENT_AUDITOR)" \
		--model "$(MODEL_AUDITOR)" \
		"Audit architectural consistency across approved ADRs and diagrams. Do not modify files."


# -----------------------------------------------------------------------------
# CI
# -----------------------------------------------------------------------------

.PHONY: ci-check
ci-check: check check-models render-check
	@echo
	@echo "CI check: OK"


# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

render: render-opencode render-agents render-commands
	@echo
	@echo "Render: OK"


.PHONY: render-opencode
render-opencode:
	@python3 scripts/render.py \
		render \
		templates/opencode.json.tpl \
		opencode.json


render-check: render-check-opencode render-check-agents render-check-commands
	@echo
	@echo "Render check: OK"


.PHONY: render-check-opencode
render-check-opencode:
	@python3 scripts/render.py \
		check \
		templates/opencode.json.tpl \
		opencode.json


.PHONY: render-agents
render-agents:
	@python3 scripts/render.py render \
		templates/AGENTS.md.tpl \
		AGENTS.md
	@python3 scripts/render.py render \
		templates/agents/architecture-finder.md.tpl \
		.opencode/agents/architecture-finder.md
	@python3 scripts/render.py render \
		templates/agents/architect.md.tpl \
		.opencode/agents/architect.md
	@python3 scripts/render.py render \
		templates/agents/adr-writer.md.tpl \
		.opencode/agents/adr-writer.md
	@python3 scripts/render.py render \
		templates/agents/adr-reviewer.md.tpl \
		.opencode/agents/adr-reviewer.md
	@python3 scripts/render.py render \
		templates/agents/consistency-auditor.md.tpl \
		.opencode/agents/consistency-auditor.md


.PHONY: render-check-agents
render-check-agents:
	@python3 scripts/render.py check \
		templates/AGENTS.md.tpl \
		AGENTS.md
	@python3 scripts/render.py check \
		templates/agents/architecture-finder.md.tpl \
		.opencode/agents/architecture-finder.md
	@python3 scripts/render.py check \
		templates/agents/architect.md.tpl \
		.opencode/agents/architect.md
	@python3 scripts/render.py check \
		templates/agents/adr-writer.md.tpl \
		.opencode/agents/adr-writer.md
	@python3 scripts/render.py check \
		templates/agents/adr-reviewer.md.tpl \
		.opencode/agents/adr-reviewer.md
	@python3 scripts/render.py check \
		templates/agents/consistency-auditor.md.tpl \
		.opencode/agents/consistency-auditor.md


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

# -----------------------------------------------------------------------------
# Project configuration validation
# -----------------------------------------------------------------------------

.PHONY: check-config
check-config:
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
	@echo "config: OK"

.PHONY: init-project
init-project:
	@if [ -f "config/project.mk" ]; then \
		echo "config/project.mk already exists"; \
	else \
		cp config/project.mk.example config/project.mk; \
		echo "created: config/project.mk"; \
	fi

# -----------------------------------------------------------------------------
# Bootstrap
# -----------------------------------------------------------------------------

.PHONY: bootstrap
bootstrap:
	@echo "Bootstrapping ADR tooling..."
	@echo
	@$(MAKE) check-config
	@$(MAKE) check-tools
	@$(MAKE) check-repository
	@$(MAKE) check-resources
	@$(MAKE) check-models
	@$(MAKE) render
	@$(MAKE) render-check
	@echo
	@echo "Bootstrap: OK"
	@echo
	@echo "Project: $(PROJECT_NAME)"
	@echo "ADR repository: $(ADR_REPO_ABS)"