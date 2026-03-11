# Round 3 — Scenario/stack modules for demo mode

Objective: collapse multi-module sequences into a few “stack” modules when in demo mode, while leaving underlying modules reusable.

- Create thin orchestrators:
  - `pathway-adx-demo.bicep`: wraps ADX + role assignments + k8s workloads + Grafana config needed for core path. Accepts a single `adxPathway` object; internally wires outputs. External wiring shrinks to 1 module call.
  - `pathway-managed-prom-demo.bicep`: wraps AMW + DCE/DCR/DCRA + recording rules + optional Prom alert. Uses `managedPromPathway` object.
  - `pathway-logs-demo.bicep`: wraps Log Analytics + diag settings + container insights.
- In `main.bicep`, keep current module calls for “advanced” mode, but add a `param demoMode bool = true`. When true, call only the scenario modules; when false, fan out to individual modules. This can cut edge count by >50% for the demo path without deleting modularity.
- Grafana integration stays clear: each stack module returns a small output (datasource info, dashboards to import) that Grafana-config consumes. That keeps “all roads lead to Grafana” narrative while hiding internal wiring.
- Testing impact: deploymentScripts stay the same; only module composition changes. We can reuse forceUpdateTag pattern to ensure Grafana-config reruns when upstream stacks change.
- Tradeoffs:
  - Scenario modules add another layer, but they isolate demo-specific defaults from reusable modules.
  - Need to ensure idempotency and avoid double-creating resources if someone mixes demo + advanced mode; guard with `if (!demoMode)` wrappers.
- Wiring reduction expectation: going from ~10 module edges to ~3–4 in demo mode, especially for identity + role assignments.
