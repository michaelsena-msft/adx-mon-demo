# Round 4 — Demo-focused simplifications

Objective: lean into “demo, not production” to prune parameters and defaults, reducing perceived wiring even without structural refactors.

- Opinionated defaults:
  - Pre-enable all pathways; make disables opt-out via parameter file only. `main.bicep` signature shrinks because `enableX` flags move to sample param files, not root.
  - Standardize locations, SKUs, retention on demo-friendly values so we drop many parameters entirely.
- Parameter file presets:
  - Ship `main.demo.bicepparam` that sets minimal required values; everything else is defaulted. Demo flow becomes `az deployment sub create ... --parameters @main.demo.bicepparam`.
  - Add optional presets per pathway (e.g., `main.prom-only.bicepparam`) to show Grafana pathways without editing `main.bicep`.
- Inline wiring helpers:
  - Use small local variables inside `main.bicep` to alias frequently reused outputs (e.g., `var grafana = grafana.outputs`). Cuts repeated long-form references that bloat wiring lines.
  - For demo, accept that some identity role assignments can be coarse-grained (assign a single MI broader rights) to reduce separate role assignment modules.
- Documentation cues:
  - README “quick start” can point to demo param file instead of enumerating all toggles. Reduced surface area = less wiring cognitive load.
- Grafana emphasis:
  - Pre-load only the two datasources (ADX + AMW) and a trimmed dashboard set; fewer conditionals in Grafana-config when running demo preset.
- Tradeoffs:
  - Less flexibility for custom SKUs/regions unless flipping to advanced mode.
  - Risk of hiding knobs people want to see; mitigate by documenting “flip to advanced” path.
