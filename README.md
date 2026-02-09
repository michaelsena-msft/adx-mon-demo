# ADX-Mon Bicep Demo

A single-command, Bicep-first deployment of [adx-mon](https://github.com/Azure/adx-mon) on AKS with Azure Data Explorer and Managed Grafana.

## What Gets Deployed

| Resource | Purpose |
|----------|---------|
| **AKS Cluster** | Hosts adx-mon collectors, ingestors, and kube-state-metrics |
| **Azure Data Explorer** | Stores metrics (608+ tables) and logs (4 tables) |
| **Managed Grafana** | Visualization — ADX datasource auto-configured, no pre-built dashboards |
| **Managed Identities** | Workload identity federation (no secrets) for adx-mon ↔ ADX |

## Quick Start

### Prerequisites

- Azure CLI with Bicep (`az bicep install`)
- An Azure subscription with Contributor access

### Deploy

```bash
# Copy and customize the parameter file
cp main.sample.bicepparam main.bicepparam
# Edit main.bicepparam with your values (principalIds, etc.)

# Deploy (takes ~20 minutes, ADX cluster is the bottleneck)
az deployment sub create \
  --location eastus2 \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name adxmon-deploy
```

### Outputs

After deployment, get your endpoints:

```bash
az deployment sub show --name adxmon-deploy --query 'properties.outputs' -o json
```

This returns:
- **ADX Web Explorer URL** — Query metrics/logs directly in the browser
- **Grafana Endpoint** — Access dashboards (you have Grafana Admin)
- **ADX Cluster URI** — For programmatic access

## Architecture

### Where Are My Metrics?

**Managed Prometheus is NOT used.** All metrics collection is handled by adx-mon:

- **adx-mon Collector** (DaemonSet) — scrapes Prometheus endpoints on every node (cadvisor, kubelet, node metrics)
- **adx-mon Collector Singleton** (Deployment) — scrapes cluster-wide endpoints (kube-apiserver)
- **kube-state-metrics** — enriches with Kubernetes metadata (pod/deployment/node state)
- **adx-mon Ingestor** (StatefulSet) — batches and writes everything to ADX

All metrics land in the **Metrics** database in ADX (~600+ auto-created tables, one per metric name).

### Where Are My Logs?

| Log Type | Location | Table |
|----------|----------|-------|
| **Infrastructure** (kubelet journal) | ADX → `Logs` database | `Kubelet` |
| **adx-mon components** (ingestor/collector) | ADX → `Logs` database | `Ingestor`, `Collector` |
| **Application logs** | Collected from containers via adx-mon annotations | ADX → `Logs` database |

To send logs from your own app, add annotations to your pod:
```yaml
annotations:
  adx-mon/log-destination: "Logs:MyAppTable"
  adx-mon/log-parsers: json
```

### Grafana

Managed Grafana is deployed with an ADX datasource pre-configured. No dashboards are pre-loaded — explore the data using Grafana's built-in query editor or create your own.

User principals specified in `userPrincipalIds` get **Grafana Admin** and **ADX Viewer** access automatically.

## Exploring the Data

### ADX Web Explorer

Open the ADX Web Explorer URL from deployment outputs, then try:

```kusto
// See all metric tables
.show tables | sort by TableName

// Sample a metric
ContainerCpuUsageSecondsTotal
| where Timestamp > ago(5m)
| take 10

// Use the prom_delta function for counter metrics
ContainerCpuUsageSecondsTotal
| where Timestamp > ago(10m)
| invoke prom_delta()
| summarize avg(Value) by Namespace, bin(Timestamp, 1m)
```

### Grafana

Navigate to the Grafana endpoint, add panels using the pre-configured ADX datasource, and query the `Metrics` or `Logs` database.

## File Structure

```
├── main.bicep                 # Subscription-scope orchestrator
├── main.sample.bicepparam     # Sample parameters (customize → main.bicepparam)
├── bicepconfig.json           # Bicep linter config
├── modules/
│   ├── aks.bicep              # AKS with OIDC + workload identity
│   ├── adx.bicep              # ADX cluster + Metrics/Logs databases
│   ├── identity.bicep         # Managed identities + federated credentials
│   ├── grafana.bicep          # Managed Grafana + user admin roles
│   ├── role-assignments.bicep # ADX RBAC (adx-mon, Grafana, user viewers)
│   ├── k8s-workloads.bicep    # Deployment script: applies K8s manifests
│   └── grafana-config.bicep   # Deployment script: ADX datasource only
└── k8s/
    ├── crds.yaml              # adx-mon Custom Resource Definitions
    ├── ingestor.yaml          # Ingestor StatefulSet
    ├── collector.yaml         # Collector DaemonSet + Singleton
    ├── ksm.yaml               # kube-state-metrics (auto-sharded)
    ├── functions.yaml         # Sample Function + ManagementCommand CRs
    └── sample-alertrule.yaml  # Sample AlertRule for pod restart detection
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `resourceGroupName` | `rg-adx-mon` | Resource group name |
| `location` | `eastus2` | Azure region |
| `aksClusterName` | `aks-adx-mon` | AKS cluster name |
| `grafanaName` | `grafana-adx-mon` | Grafana workspace name |
| `userPrincipalIds` | `[]` | User object IDs for ADX Viewer + Grafana Admin |
| `userTenantId` | current tenant | Tenant for user principals |
