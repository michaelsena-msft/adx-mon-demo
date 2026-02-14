# Round 5 — Recommended hybrid path to 50% less wiring

Objective: pick the smallest set of changes that deliver ~50% wiring reduction while keeping modularity for reuse.

- Proposed combo:
  1) Adopt pathway objects (`adxPathway`, `managedPromPathway`, `logsPathway`) + `contacts` bundle to shrink root parameter list and module signatures.
  2) Add `demoMode` switch that routes through scenario stack modules (one per pathway). Default `demoMode = true` for demos; advanced users flip to false to use fine-grained modules.
  3) Ship `main.demo.bicepparam` using opinionated defaults; hide most toggles there.
- Wiring reduction estimate:
  - Root parameter count drops from dozens to ~6–8 (pathway objects + contacts + demoMode).
  - Module edges during demo drop to: AKS/ADX/Grafana + 3 scenario modules + Grafana-config (6–7 edges vs ~12–14 today).
  - Grafana-config input count shrinks because pathway objects carry enable flags + endpoints together.
- Grafana alignment:
  - Each scenario module returns a small `datasourceDescriptor` (type, url, credentials hint) and `dashboards` list. Grafana-config iterates over descriptors to provision datasources/dashboards uniformly, keeping “all roads lead to Grafana” messaging clear.
- Safety/maintenance:
  - Underlying modules remain intact; scenario modules simply compose them. Advanced users can still call modules directly or rewire them in their own `main`.
  - Keep deploymentScripts and forceUpdateTag behavior unchanged to avoid regressions.
- Next steps to implement:
  - Define pathway/contacts type aliases in `bicepconfig`.
  - Introduce scenario modules and `demoMode` gate in `main.bicep`.
  - Update sample param files and README quick start to point at `main.demo.bicepparam`.
