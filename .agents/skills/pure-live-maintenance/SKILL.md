---
name: pure-live-maintenance
description: Diagnose Pure Live bugs and review Issues or code changes while preserving existing behavior. Use for bug fixes or Issue reviews; not ordinary wording edits or standalone builds.
---

# Pure Live Maintenance

<!-- maintenance-skill-markers: bug-provenance-required; semantic change ledger -->

Use [MAINTENANCE_POLICY.md](../../../MAINTENANCE_POLICY.md) for provenance and product invariants. Read only the sections relevant to the task.

- Trace the symptom to the first invalid state, its owner and affected modes. Record the local SHA and evidence-backed provenance; inspect relevant Git history as needed. Pending provenance does not block an independently supported local repair.
- Build a focused reproduction, fix the cause and check callers. Use [AGENT_WORKFLOW.md](../../../docs/AGENT_WORKFLOW.md) for risk-based regression, especially lifecycle, retries, persistence and source switches.
- Larger or cross-module changes keep a semantic change ledger: purpose, before/after behavior, impact on customized features and disposition for each change.
- Delivery follows `bugfix-android-release-default` in [BUILD_POLICY.md](../../../BUILD_POLICY.md); retain pending evidence and respect an analysis-only/deferred request.

Device access and Issue intake follow AGENTS.md.
