# Round 2 — Parameter/output bundles to trim edges

Objective: cut wiring by grouping related knobs so fewer discrete params/outputs cross module boundaries.

- Pathway packs: define three objects (adxPathway, managedPromPathway, logsPathway). Each holds enable flag + required settings. `main.bicep` takes these objects, passes them wholesale to child modules, and child modules pick what they need. Reduces dozens of scalar params to 3 objects.
- Identity block: wrap managed identity names/ids/principalIds into a single `deployIdentities` object. Downstream modules accept the object instead of individual strings. Cuts repeated `param ...IdentityPrincipalId`/`identityResourceId`.
- Contacts block: consolidate alert owners, Grafana admins, ADX viewers into `contacts` with sub-arrays. Role assignments module consumes it once; Grafana-config module can reuse the same list for admin role mapping. Removes duplicate parameter definitions.
- Endpoint bundle: expose one `connectivity` object carrying kubeconfigs, Grafana endpoint, ADX endpoints. Modules needing any endpoint pick from the object, avoiding separate outputs/params per endpoint.
- Conditional packaging: Instead of `param enableManagedPrometheus bool` at root and again in submodules, embed `enabled` boolean inside each pathway object; when disabled, avoid emitting outputs. Halves the number of conditional `if (...)` wires.
- For demo simplicity: maintain strongly-typed aliases for these objects in `bicepconfig` to keep authoring ergonomic.
- Tradeoffs:
  - Slightly less explicit module contracts; readers need to drill into object shapes to see dependencies.
  - Existing parameter files need translation once; acceptable for demo if we ship updated samples.
- How it helps Grafana story: Grafana-config only needs `contacts`, `connectivity`, and flags from `pathway` objects to know what datasources/dashboards to create. One input object instead of multiple booleans/urls shortens wiring count.
