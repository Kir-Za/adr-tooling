# ADR Architecture Governance

This repository contains tooling for AI-assisted Architecture Decision Record development.

The architecture artifacts themselves are stored in:

`${ADR_REPO_ABS}`

## Repository layout

Canonical ADR template:

`${ADR_TEMPLATE_ABS}`

Proposed ADRs:

`${ADR_PROPOSED_ABS}/`

Approved ADRs:

`${ADR_APPROVED_ABS}/`

Architecture diagrams:

`${ADR_DIAGRAMS_ABS}/`

## Source of truth

Approved ADRs are the authoritative source of architectural decisions.

Proposed ADRs are drafts and must not be treated as accepted architecture.

The canonical ADR template defines the required ADR structure.

Architecture diagrams are supporting architectural artifacts.

If an approved ADR and a diagram conflict, report the inconsistency instead of silently choosing one.

## ADR lifecycle

The lifecycle is:

`proposed -> human review -> approved`

AI agents may create or modify ADRs only under:

`${ADR_PROPOSED_ABS}/`

AI agents must not:

- modify approved ADRs;
- modify the canonical ADR template;
- move ADRs from proposed to approved;
- treat an AI review verdict as human approval.

Only the human review and Git workflow may make an ADR approved.

## ADR structure

Every new ADR must follow:

`${ADR_TEMPLATE_ABS}`

The ADR has two distinct parts.

### Human Architecture View

The first part is written primarily for people.

It describes architecture approximately at C4 levels C1-C3:

- system context;
- containers and their responsibilities;
- significant components;
- important runtime flows and architectural behavior.

It must not descend into implementation details such as classes or methods unless those details are themselves part of a public architectural contract.

### LLM Contract

The second part is a normalized machine-oriented representation of the architectural decision.

It is not constrained by C4 notation.

Its purpose is to support:

- architecture retrieval;
- dependency analysis;
- consistency checking;
- implementation planning;
- implementation verification;
- protocol and shared-library design.

The LLM Contract must be explicit and concise.

Use `NONE` when a template section is intentionally not applicable.

Do not omit a section merely because no data was found.

## Architecture analysis rules

Before proposing or modifying an architectural decision:

1. Read the canonical ADR template.
2. Search approved ADRs for related decisions.
3. Inspect relevant architecture diagrams.
4. Identify existing constraints and terminology.
5. Separate facts, assumptions and proposed decisions.
6. Identify potential conflicts with approved ADRs.
7. Identify whether the decision introduces or modifies architectural contracts.
8. Identify whether diagrams may require updates.

Do not assume that implementation overrides an approved ADR.

If implementation conflicts with an approved ADR, report architecture drift.

## ADR consistency

When reviewing an ADR, check at least:

- compliance with the canonical template;
- consistency with approved ADRs;
- conflicting or overlapping decisions;
- terminology consistency;
- architectural contract compatibility;
- missing or incorrect architecture relations;
- contradictions between the Human Architecture View and the LLM Contract;
- contradictions with diagrams;
- missing implementation obligations;
- unsupported assumptions.

Classify findings as:

- BLOCKER
- CONFLICT
- INCONSISTENCY
- RISK
- MISSING_INFORMATION
- SUGGESTION

## Decision discipline

Do not silently resolve contradictions.

Do not invent requirements, constraints, relationships or implementation obligations.

If information is insufficient, state it explicitly.

When drafting an ADR, preserve the architectural decision already agreed in the current workflow.

Formatting an ADR must not become an opportunity to redesign the solution.