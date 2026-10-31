---
name: openflowkit-architecture
description: Use OpenFlowKit for architecture visualization, repository discovery, validation, and drift analysis while preserving ADR authority.
compatibility: opencode
---

# OpenFlowKit Architecture
OpenFlowKit output is evidence or visualization, not automatic architectural authority. Approved ADRs remain authoritative.

For standalone diagrams: establish semantics first → inspect existing state → get syntax when needed → create/update representation → validate → save/export as appropriate → verify consistency with ADRs.

`analyze_codebase` and `discover_architecture` produce implementation evidence. `drift_report` detects likely drift but cannot infer intent. Classify differences before acting.

Standalone diagram mutation belongs to the Architect. ADR Writer may only materialize embedded Mermaid and use validation-only capabilities.
