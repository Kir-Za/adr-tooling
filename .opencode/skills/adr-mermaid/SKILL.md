---
name: adr-mermaid
description: Create or update Mermaid embedded in a proposed ADR without changing the underlying architecture decision.
compatibility: opencode
---

# ADR Mermaid
Use only after diagram semantics are established. Convert those semantics into the smallest useful Mermaid diagram, keep it consistent with ADR prose/invariants/contracts, and validate syntax when a permitted tool exists.

Do not invent components, relations, flows, responsibilities, or constraints. Do not mutate standalone architecture diagrams. If prose and diagram disagree and intent is unclear, report the inconsistency rather than choosing one arbitrarily.
