# adx-mon Bicep Demo

A single-command Bicep deployment of [adx-mon](https://github.com/Azure/adx-mon) on AKS.
adx-mon scrapes Prometheus-format metrics and container logs, stores them in
[Azure Data Explorer (ADX)](https://learn.microsoft.com/en-us/azure/data-explorer/), and
visualizes everything through [Managed Grafana](https://learn.microsoft.com/en-us/azure/managed-grafana/).

## Architecture

```mermaid
flowchart LR
    subgraph AKS["AKS Cluster"]
        CD["Collector\nDaemonSet\n(per node)"]
        CS["Collector\nSingleton"]
        KSM["kube-state-metrics"]
        ING["Ingestor\nStatefulSet"]
    end

    CD -- scrapes --> cAdvisor["cAdvisor /\nkubelet"]
    CD -- scrapes --> Pods["Annotated\nPods"]
    CS -- scrapes --> API["kube-apiserver"]
    KSM -. scraped by .-> CD

    CD --> ING
    CS --> ING

    ING -- batch write --> MetricsDB[("ADX\nMetrics DB\n~680 tables")]
    ING -- batch write --> LogsDB[("ADX\nLogs DB")]

    MetricsDB --> Grafana["Managed\nGrafana"]
    LogsDB --> Grafana

    %% Managed Prometheus (enabled by default, can be disabled)
    AKS -. "scrape (ama-metrics)" .-> AMW["Azure Monitor\nWorkspace"]
    AMW -. linked .-> Grafana

    %% Diagnostic Settings (enabled by default, can be disabled)
    AKS -. "control-plane logs" .-> LAW["Log Analytics\nWorkspace"]

    %% Container Insights (enabled by default, can be disabled)
    AKS -. "container logs\n(ama-logs)" .-> LAW

    style AKS fill:#e8f4fd,stroke:#0078d4
    style MetricsDB fill:#fff3cd,stroke:#d4a017
    style LogsDB fill:#fff3cd,stroke:#d4a017
    style Grafana fill:#d4edda,stroke:#28a745
    style AMW fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style LAW fill:#e8f0fe,stroke:#1a73e8,stroke-dasharray: 5 5
```

**Solid lines** = core ADX/Kusto pathway (implemented by adx-mon, always deployed).
**Dashed lines** = [Managed Prometheus](#managed-prometheus-enabled-by-default), [Diagnostic Settings](#aks-diagnostic-settings-enabled-by-default), and [Container Insights](#container-insights-enabled-by-default) — enabled by default but can be disabled.

Each Prometheus metric becomes its own table in the **Metrics** database (~680+ tables).
Logs land in tables created per [`log-destination` annotation](#logs-pod-annotations) in the
**Logs** database. System tables (`Collector`, `Ingestor`, `Kubelet`) are created automatically.

## Pathway Terminology Reference

Use **ADX/Kusto pathway** when describing the ADX data path. Use **adx-mon** for the collector/ingestor implementation that powers that pathway.

| Pathway name | Underlying tech name | Key terminology |
|---|---|---|
| ADX/Kusto pathway (via adx-mon) | Azure Data Explorer (ADX, Kusto engine) | Collector, Ingestor, Metrics DB, Logs DB, KQL |
| Managed Prometheus pathway | Azure Monitor Workspace (AMW) for Prometheus metrics | ama-metrics, DCE, DCR, DCRA, PromQL, recording rules |
| Geneva pathway (WIP) | Geneva data pipeline (MDM + MDSD) | StatsD, MetricsExtension, Fluentd, MDM, MDSD, warm path |

## Bicep Module Graph

`main.bicep` is the vanilla entrypoint (creates resource group + AKS), then invokes `observability.bicep`.
`observability.bicep` orchestrates the resource-group-scoped modules below. **Solid lines** = always deployed.
**Dashed lines** = conditionally deployed (enabled by default, can be disabled).

```mermaid
flowchart TD
    main["main.bicep\n(subscription scope)"]
    obs["observability.bicep\n(resource group scope)"]

    main --> aks["aks.bicep\nAKS + ACNS"]
    main --> obs
    obs --> grafana["grafana.bicep\nManaged Grafana"]

    obs --> adx["modules/adx/cluster.bicep\nADX + Databases"]
    obs --> identity["modules/adx/identity.bicep\nadx-mon + AKS script identity"]

    adx & identity & grafana --> adxRbac["modules/adx/rbac.bicep\nADX DB RBAC"]

    aks & adx & identity --> k8s["modules/adx/workloads.bicep\nadx-mon + demo-app"]

    obs --> gconfigId["modules/grafana/config-deployer-identity.bicep\nGrafana config identity"]
    grafana & adx & gconfigId --> gconfig["modules/grafana/bind-adx-datasource.bicep\nADX datasource + dashboards"]
    grafana --> gadmins["modules/grafana/admin-rbac-users.bicep\nGrafana Admin users"]

    %% Managed Prometheus + alerts (optional)
    obs -.-> mp["modules/azure-monitor/managed-prometheus.bicep\nAMW + DCE/DCR/DCRA"]
    mp & aks -.-> rules["modules/azure-monitor/prometheus-rules.bicep\nRecording rules"]
    obs -.-> ag["modules/azure-monitor/action-group.bicep\nAction Group"]
    mp & aks & ag -.-> recAlerts["modules/azure-monitor/recommended-metric-alerts.bicep\nRecommended alerts"]
    mp & aks & ag -.-> demoAlert["modules/azure-monitor/simple-prometheus-alert.bicep\nDemo Prometheus alert"]
    obs -.-> amwBind["modules/grafana/bind-amw.bicep\nGrafana AMW link + RBAC"]

    %% Logs (optional)
    obs -.-> law["modules/azure-monitor/log-analytics.bicep\nLog Analytics"]
    law & aks -.-> diag["modules/azure-monitor/diagnostic-settings.bicep\nControl-plane logs"]
    law & aks -.-> ci["modules/azure-monitor/container-insights.bicep\nContainer logs + inventory"]
    mp -.->|shares DCE| ci
    obs -.-> lawBind["modules/grafana/bind-law.bicep\nGrafana LAW RBAC"]

    style mp fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style rules fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style ag fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style recAlerts fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style demoAlert fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style amwBind fill:#f0e6ff,stroke:#7b2ff7,stroke-dasharray: 5 5
    style law fill:#e8f0fe,stroke:#1a73e8,stroke-dasharray: 5 5
    style diag fill:#e8f0fe,stroke:#1a73e8,stroke-dasharray: 5 5
    style ci fill:#e8f0fe,stroke:#1a73e8,stroke-dasharray: 5 5
    style lawBind fill:#e8f0fe,stroke:#1a73e8,stroke-dasharray: 5 5
```

## Quick Start

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) with [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview) (`az bicep install`)
- An Azure subscription with **Contributor** access

### Entry points

- `main.bicep` (subscription scope): creates the resource group, creates AKS, then deploys the full observability stack.
- `observability.bicep` (resource-group scope): deploys observability components onto an existing AKS cluster using `aksClusterResourceId`.

### 1. Configure Parameters

```bash
cp main.sample.bicepparam main.bicepparam
```

Edit `main.bicepparam`:
- set one or more **alert email receivers** for Azure Monitor alerts (Action Group is created by this deployment)
- set one or more **alert owner/contact identifiers**

```bicep
param alertEmailReceivers = [
  {
    name: 'primary'
    emailAddress: 'yourname@yourtenant.onmicrosoft.com'
  }
]

param alertOwnerIds = [
  'youralias'
]
```

`main.bicep` intentionally keeps a lean parameter surface. For access grants and advanced observability
overrides (for example `userPrincipalNames`, `forceScriptRerun`, feature toggles, and custom dashboards),
deploy `observability.bicep` directly.

### 2. Deploy

```bash
az deployment sub create \
  --location eastus2 \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name adxmon-deploy
```

Existing AKS attach-only flow:

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file observability.bicep \
  --parameters aksClusterResourceId=<aks-resource-id> \
  --parameters alertEmailReceivers='[{\"name\":\"primary\",\"emailAddress\":\"you@contoso.com\"}]' \
  --parameters alertOwnerIds='[\"youralias\"]' \
  --name adxmon-observability-deploy
```

Deployment takes **~15 minutes** on a fresh deploy (ADX cluster provisioning is the bottleneck).
Update deploys (no-change or parameter-only changes) take **~4–5 minutes** — deployment scripts
are skipped automatically when their inputs haven't changed.

> **Tip**: Add `--no-wait` to return immediately and monitor via `az deployment sub show --name adxmon-deploy`.

> **Faster iterative deploys** (Azure CLI 2.76+): Skip full RBAC preflight validation with
> `--validation-level ProviderNoRbac` to save a few seconds per deployment:
>
> ```bash
> az deployment sub create \
>   --location eastus2 \
>   --template-file main.bicep \
>   --parameters main.bicepparam \
>   --validation-level ProviderNoRbac \
>   --name adxmon-deploy
> ```

### 3. Verify

```bash
az deployment sub show --name adxmon-deploy --query 'properties.outputs' -o json
```

This returns:

| Output | Use |
|--------|-----|
| `aksClusterName` | AKS cluster name (for `az aks get-credentials`) |
| `adxWebExplorerUrl` | Query metrics and logs in the [ADX Web Explorer](https://learn.microsoft.com/en-us/azure/data-explorer/web-query-data) |
| `adxAlertDemoUrl` | Open ADX with the sample alert query preloaded (demo of the ADX alert pathway) |
| `grafanaEndpoint` | Build dashboards (you have Grafana Admin). Explore: append `/explore`. |
| `azureMonitorWorkspaceId` | AMW resource ID (present when Managed Prometheus is enabled) |
| `logAnalyticsPortalUrl` | Log Analytics query portal (present when Diagnostic Settings or Container Insights is enabled) |
| `azureMonitorAlertPortalUrls` | Azure portal browse URL for Prometheus rule groups (single URL entry) |

## Collecting Your Application Data

### Metrics (Pod Annotations)

Annotate your pod spec so the adx-mon Collector scrapes Prometheus metrics:

```yaml
annotations:
  adx-mon/scrape: "true"
  adx-mon/port: "8080"
  adx-mon/path: "/metrics"
```

You can also push metrics via [Prometheus remote write](https://prometheus.io/docs/concepts/remote_write_spec/) to the Collector at `:3100/receive`.

### Logs (Pod Annotations)

Route container logs to a custom ADX table:

```yaml
annotations:
  adx-mon/scrape: "true"               # required — gates ALL discovery
  adx-mon/log-destination: "Logs:MyAppTable"
  adx-mon/log-parsers: json
```

> **Important**: `adx-mon/scrape: "true"` is required for **both** metrics and log discovery.
> Without it, adx-mon will not discover the pod at all — even if `log-destination` is set.

> **System / unowned pods**: Pods without annotations (e.g., `kube-system`) can be patched with
> `kubectl patch` to add `adx-mon/scrape` + `adx-mon/log-destination`. This causes a rolling restart.
> See the [adx-mon configuration reference](https://github.com/Azure/adx-mon#configuration) for details.

## Managed Prometheus (enabled by default)

[Managed Prometheus](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
can run **alongside** adx-mon — both scrape the same Prometheus endpoints independently.

To disable (when deploying `observability.bicep` directly):
```bicep
param enableManagedPrometheus = false
```

When enabled, Bicep deploys an [Azure Monitor Workspace (AMW)](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/azure-monitor-workspace-overview),
[data-collection endpoint/rule](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview), links the AMW to Grafana,
and creates [Prometheus recording rule groups](https://learn.microsoft.com/azure/azure-monitor/containers/prometheus-metrics-scrape-default#recording-rules)
required by the auto-provisioned Kubernetes Compute dashboards.
See `modules/azure-monitor/prometheus-rules.bicep` for details on why these are declared explicitly.

This deployment also enables Azure Monitor [recommended AKS metric alerts](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-metric-alerts)
using Microsoft's published template and adds one simple custom Prometheus alert rule group as an example.

Log-based Azure Monitor alert rules (`scheduledQueryRules`) are intentionally out of scope in this repo.
This deployment applies the [full metrics profile](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-scrape-default)
and pod-annotation scraping via [`ama-metrics-settings-configmap`](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-scrape-configuration).
This means custom app metrics (e.g., `nginx_http_requests_total`) appear in both ADX **and** Managed Prometheus — a true dual-pipeline.

### Control plane metrics (preview)

AKS control plane metrics (for example `controlplane-apiserver` / `controlplane-etcd`) are a **preview** feature for the managed service for Prometheus.
Follow the official guide: [Monitor Azure Kubernetes Service control plane metrics (preview)](https://learn.microsoft.com/azure/aks/control-plane-metrics-monitor).

At a high level, you must:

```azurecli
# Install the aks-preview extension
az extension add --name aks-preview

# Register the feature flag
az feature register --namespace "Microsoft.ContainerService" --name "AzureMonitorMetricsControlPlanePreview"

# After it shows as Registered, refresh the provider registration
az provider register --namespace "Microsoft.ContainerService"
```

See [COMPARISONS.md](COMPARISONS.md) for a detailed coverage comparison.

## AKS Diagnostic Settings (enabled by default)

Send AKS control-plane logs to a [Log Analytics workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)
for audit and troubleshooting. [Microsoft recommends](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-resource-logs)
enabling this for all AKS clusters.

To disable (when deploying `observability.bicep` directly):
```bicep
param enableDiagnosticSettings = false
```

When enabled, Bicep deploys a Log Analytics workspace and configures these categories:
[`kube-audit-admin`](https://learn.microsoft.com/en-us/azure/aks/monitor-aks-reference#resource-logs), `kube-controller-manager`, `cluster-autoscaler`, `guard`.

> **Cost note**: `kube-audit-admin` is used instead of `kube-audit` (full), which excludes
> GET/LIST requests and is [significantly cheaper](https://learn.microsoft.com/en-us/azure/aks/monitor-aks-reference#resource-logs).

## Container Insights (enabled by default)

[Container Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
collects container logs and Kubernetes inventory data to a Log Analytics workspace — the log equivalent of what
[Managed Prometheus](#managed-prometheus-enabled-by-default) does for metrics.

To disable (when deploying `observability.bicep` directly):
```bicep
param enableContainerInsights = false
```

When enabled, Bicep deploys a [data-collection rule/endpoint](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview),
enables the `omsagent` AKS addon (which deploys `ama-logs` DaemonSet pods), and grants Grafana read access to the workspace.

**Tables collected** (the "Logs and events" grouping):

| Table | Contents |
|-------|----------|
| `ContainerLogV2` | stdout/stderr from **all** containers (auto-discovered, no annotations needed) |
| `KubePodInventory` | Pod phase, image, conditions — structured inventory with no adx-mon equivalent |
| `KubeEvents` | Kubernetes events (scheduled, pulled, started, killed) |

**Namespace filtering**: `kube-system` is excluded to reduce noise. To capture specific `kube-system` workloads
(e.g., coredns), adjust the DCR's `namespaceFilteringMode` in `modules/azure-monitor/container-insights.bicep`.

See [COMPARISONS.md](COMPARISONS.md) for a 3-way coverage comparison.

## Advanced Container Networking Services (ACNS)

[ACNS](https://learn.microsoft.com/azure/aks/advanced-container-networking-services-overview) is
always enabled. It provides network observability for AKS via Hubble/Cilium metrics. When Managed
Prometheus is also enabled, the auto-provisioned Kubernetes Networking dashboards in Grafana
populate with flow data automatically.

## Grafana Dashboards

A bundled **Demo App** dashboard is deployed automatically with panels arranged for side-by-side comparison:

| ADX/Kusto (via adx-mon) | Managed Prometheus | Container Insights |
|---|---|---|
| Request Rate (`NginxHttpRequestsTotal`) | Request Rate (`nginx_http_requests_total`) | — |
| Container CPU | Container CPU | — |
| Container Memory | — | Demo App Logs (`ContainerLogV2`) |
| Demo App Logs (ADX) | — | — |

The dashboard JSON lives in `dashboards/demo-app.json`. To add your own dashboards (when deploying `observability.bicep` directly), pass
`dashboardDefinitions` — an array of `{ title, definition }` objects:

> The built-in Container Insights panel uses a `__LAW_RESOURCE_ID__` placeholder, replaced at deployment time with the current Log Analytics workspace resource ID.

```bicep
param dashboardDefinitions = [
  {
    title: 'My Dashboard'
    definition: { /* Grafana JSON model */ }
  }
]
```

The deployment script calls `az grafana dashboard create` for each entry.

## Future: Geneva Integration

[Geneva](https://eng.ms/docs/products/geneva/getting_started/environments/akslinux) (Microsoft's internal monitoring platform) can coexist with adx-mon on the same AKS cluster. The ADX/Kusto pathway and Geneva pathway run independently and do not conflict.

| Signal | Geneva pathway details |
|--------|-------------|
| Metrics | StatsD → MetricsExtension → MDM, or Managed Prometheus pathway (ama-metrics → AMW) → MDM |
| Logs | stdout → Fluentd → MDSD → Geneva warm path |

Geneva agent deployment uses Kubernetes manifests (Helm/YAML), not Bicep. See the [Geneva on AKS guide](https://eng.ms/docs/products/geneva/getting_started/environments/akslinux) for setup.
