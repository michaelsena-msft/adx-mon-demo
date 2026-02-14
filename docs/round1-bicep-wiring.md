# Round 1 — What “wiring” means today

- Current graph (per README) fans out from `main.bicep` into AKS, ADX, Grafana, then fans back in through role assignments, k8s workloads, Grafana config, optional Managed Prometheus + alerts, and optional Log Analytics + diag/container insights. Wiring = every module edge, every output that is plumbed into another module, and every conditional toggle that gates those edges.
- Pain points that inflate wiring lines:
  - Identity outputs flow to several modules (roles, k8s workloads, Grafana config).
  - Optional pathways (Managed Prometheus, Diagnostics, Container Insights, demo Prom alerts) add conditional parameters/outputs.
  - Duplication of “owner” objects (alert owners, Grafana admins, ADX viewers) across modules.
  - Repeated parameter shapes for endpoints (ingestor fqdn, grafana uri, aks kubeconfigs) that could be grouped.
- Success target: cut visible edge count / plumbing by ~50% without deleting pathways we want to showcase. Because this is a demo, tolerance for “opinionated defaults” is high — we can pre-wire the common path and hide switches in parameter files instead of main surface area.
- Observability pathways we must still tell a story about:
  - Core ADX/Kusto via adx-mon (collector/ingestor → ADX → Grafana datasources + dashboards).
  - Managed Prometheus (AMW + DCE/DCR/DCRA → Grafana).
  - Control-plane + container logs via Log Analytics / Container Insights → Grafana.
- Constraints to respect:
  - Stay modular enough to point at individual modules if someone wants to reuse them.
  - Avoid ARM runtime pitfalls (spread operator, forceUpdateTag quirks, shallowMerge) when refactoring.
  - Keep “single-command deploy” feel; no interactive prep.

Early ideas to test in later rounds:
1) Bundle pathway-specific params/outputs into structs to reduce edge counts.
2) Introduce “scenario” modules that collapse 3–5 modules behind one call for demos.
3) Ship preset parameter files per pathway and simplify `main.bicep` signature.
