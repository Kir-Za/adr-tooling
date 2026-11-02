# ADR repository

# Repositories are expected as siblings in the workspace directory.
ADR_REPO ?= ../acm-adr
ADR_TEMPLATE := docs/adrs/ai/template.md
ADR_APPROVED := docs/adrs/ai/approved
ADR_PROPOSED := docs/adrs/ai/proposed
ADR_DIAGRAMS := docs/diagrams


# LLM models

MODEL_ARCHITECT := openai/gpt-6-astra
MODEL_WRITER := openai/gpt-6-sol
MODEL_REVIEWER := openai/gpt-6-astra
MODEL_FINDER := openai/gpt-6-luna-fast
MODEL_AUDITOR := openai/gpt-6-astra


# Langfuse

LANGFUSE_ENABLED := 0
LANGFUSE_BASE_URL := http://localhost:3000
LANGFUSE_PROMPT_LABEL := production
LANGFUSE_SECRETS_FILE := config/langfuse.secrets.json
