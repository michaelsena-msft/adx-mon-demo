# adx-mon Bicep Demo

Deploy [adx-mon](https://github.com/Azure/adx-mon) on AKS with two observability pathways.
This demo is about viewing the same AKS workload signals through both pathways, then comparing in Grafana.

- **ADX/Kusto pathway**: adx-mon Collector/Ingestor writes metrics and logs to [Azure Data Explorer (ADX)](https://learn.microsoft.com/en-us/azure/data-explorer/).
- **Azure Monitor pathway**: AKS managed Prometheus pipeline writes metrics to an [Azure Monitor Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/azure-monitor-workspace-overview) with alerting and Grafana integration.

## Architecture

```mermaid
flowchart LR
    subgraph AKS["AKS Cluster"]
        APP["Workloads"]
        ADXMON["adx-mon\ncollector + ingestor"]
        AMA["Azure Monitor agents\n(ama-metrics / ama-logs)"]
    end

    APP -->|Prometheus + logs| ADXMON
    ADXMON --> ADX[("ADX\nMetrics + Logs DBs")]

    APP -.->|Prometheus scrape| AMA
    AMA -.-> AMW[("Azure Monitor Workspace")]
    AKS -.->|Control-plane logs| LAW[("Log Analytics Workspace")]
    AKS -.->|Container logs + inventory| LAW

    ADX --> GRAFANA["Managed Grafana"]
    AMW -.-> GRAFANA
    LAW -.-> GRAFANA
```

Solid lines are the ADX pathway. Dashed lines are Azure Monitor integrations (enabled by default, independently toggleable in `observability.bicep`).

## Repository Structure

- **`main.bicep`** (subscription scope): creates resource group + AKS, then invokes `observability.bicep`.
- **`observability.bicep`** (resource-group scope): orchestrates observability modules and exposes deployment outputs.
- **`modules/adx`**: ADX cluster/databases, identities, RBAC, and adx-mon Kubernetes workload deployment.
- **`modules/azure-monitor`**: Managed Prometheus, recording rules, metric alerts, diagnostic settings, and Container Insights.
- **`modules/grafana`**: Grafana provisioning, RBAC, datasource wiring, and dashboard provisioning.

## Quick Start

```bash
# 1) Copy parameters, set values in main.bicepparam, then deploy
cp main.sample.bicepparam main.bicepparam
az deployment sub create \
  --location eastus2 \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name adxmon-deploy

# 2) Read outputs (URLs, endpoints, IDs)
az deployment sub show --name adxmon-deploy --query 'properties.outputs' -o json

```

## Observability Pathways

### ADX

Implemented by [`modules/adx`](modules/adx): ADX cluster/databases, identities/RBAC, and adx-mon workload deployment.
Use `adxAlertDemoUrl` for the sample alert query deep link (`adxWebExplorerUrl` is the general ADX entry point).

### Azure Monitor

Implemented by [`modules/azure-monitor`](modules/azure-monitor): managed Prometheus collection, recording rules, metric alerting, diagnostic settings, and Container Insights.
AKS advanced networking observability (ACNS) is enabled in [`modules/aks.bicep`](modules/aks.bicep) and contributes networking signals to the Azure Monitor pathway.

Use output `azureMonitorAlertPortalUrls[0]` for the portal browse location of Prometheus rule groups:
`https://portal.azure.com/#view/HubsExtension/BrowseResource/resourceType/Microsoft.AlertsManagement%2FprometheusRuleGroups`

Also in the Azure Monitor side of this deployment (logs/inventory):

- [`diagnostic-settings.bicep`](modules/azure-monitor/diagnostic-settings.bicep): AKS control-plane resource logs to Log Analytics.
- [`container-insights.bicep`](modules/azure-monitor/container-insights.bicep): `ContainerLogV2`, `KubePodInventory`, `KubeEvents` via `ama-logs`.
- [`k8s/ama-metrics-settings.yaml`](k8s/ama-metrics-settings.yaml): metrics scrape profile (including baseline control-plane targets `controlplane-apiserver` and `controlplane-etcd`) and pod-annotation scraping settings used by Azure Monitor metrics collection.

#### Enabling More Data

Want more control-plane metrics? Review the available targets in Microsoft documentation, then add the targets you want under `default-scrape-settings-enabled` in [`k8s/ama-metrics-settings.yaml`](k8s/ama-metrics-settings.yaml).

- Docs: https://learn.microsoft.com/azure/aks/control-plane-metrics-monitor#customize-control-plane-metrics

## Deployment Outputs (demo-first)

| Output | Use |
| --- | --- |
| `adxWebExplorerUrl` | ADX web UI entry point (queries + native dashboards) |
| `adxAlertDemoUrl` | ADX sample alert query deep link |
| `grafanaEndpoint` | Managed Grafana endpoint |
| `azureMonitorAlertPortalUrls[0]` | Azure portal browse URL for Prometheus rule groups |

Additional outputs are still available from `az deployment ... --query 'properties.outputs'`.

## ADX Dashboards (native)

- Open `adxWebExplorerUrl`, then use **Dashboards** in the ADX web UI.
- The ADX web UI includes a samples gallery with built-in dashboard examples.
- This deployment does not auto-provision a cluster-specific ADX dashboard pack in ADX.

## Grafana Dashboards

[`dashboards/demo-app.json`](dashboards/demo-app.json) is provisioned by default through [`modules/grafana/bind-adx-datasource.bicep`](modules/grafana/bind-adx-datasource.bicep).
When Managed Prometheus is enabled, deployment also imports Grafana gallery dashboards:
- API server: https://grafana.com/grafana/dashboards/20331-kubernetes-api-server/
- etcd: https://grafana.com/grafana/dashboards/20330-kubernetes-etcd/

For additional dashboards, set `dashboardDefinitions` in [`observability.bicep`](observability.bicep).
