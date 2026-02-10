# ADX-Mon Research Document

## 1. What is ADX-Mon

**ADX-Mon** is an open-source, comprehensive observability platform built by Microsoft (hosted at [github.com/Azure/adx-mon](https://github.com/Azure/adx-mon)) that can unify **metrics, logs, traces, and continuous profiling** into a single stack, powered by **Azure Data Explorer (ADX/Kusto)**.

> ⚠️ **Note:** While the adx-mon platform supports traces and continuous profiling, **our deployment only uses metrics and logs collection**. Trace and profiling support exist in the collector/ingestor but are not configured in this repo's manifests.

It addresses the traditional challenges of:
- **Data silos** — metrics, logs, and traces are stored together in ADX, queryable with a single language (KQL)
- **Cardinality/scale limitations** — ADX has no restrictions on metric cardinality, retention, or granularity
- **Cost** — uses ADX's columnar storage and compression instead of Azure Monitor Workspace pricing

> **Key distinction:** In our deployment, adx-mon replaces the need for Azure Managed Prometheus. No Azure Monitor Workspace is deployed — all Prometheus-compatible metrics go directly to ADX. This is an **architectural choice** we've made; adx-mon itself is not officially positioned as a Managed Prometheus replacement by Microsoft.

**Sources:** [GitHub README](https://github.com/Azure/adx-mon), [Official docs](https://azure.github.io/adx-mon/concepts/), local `README.md`

---

## 2. Architecture

### Data Flow
```
Prometheus endpoints ──▶ Collector (DaemonSet) ──▶ Ingestor (StatefulSet) ──▶ Azure Data Explorer
Pod logs             ──▶ Collector              ──▶ Ingestor              ──▶ ADX (Logs database)
Host/journal logs    ──▶ Collector              ──▶ Ingestor              ──▶ ADX (Logs database)
OTLP logs            ──▶ Collector              ──▶ Ingestor              ──▶ ADX (supported, configured via otel-log)
OTLP traces          ──▶ Collector              ──▶ Ingestor              ──▶ ADX (supported, NOT deployed in this repo)
```

### Components

| Component | K8s Workload | Purpose |
|-----------|-------------|---------|
| **Collector** | DaemonSet (per-node) + optional Singleton (1 replica) | Scrapes Prometheus endpoints, collects logs from pods/host, accepts OTLP and remote-write. Buffers in local WAL. |
| **Ingestor** | StatefulSet | Receives telemetry from Collectors, batches into large compressed segments (100MB–1GB), uploads to ADX via Kusto ingestion API. Supports peer-transfer for coalescing small segments. |
| **Alerter** | (optional, **not deployed in this repo**) | Executes AlertRule CRDs — runs KQL queries on schedule and fires notifications. Requires separate deployment. |
| **Operator** | (optional, **not deployed in this repo**) | Manages Collector/Ingestor via CRDs for declarative configuration. We deploy components directly via manifests instead. |
| **kube-state-metrics** | StatefulSet (sharded) | Standard KSM, scraped by Collector for Kubernetes object state metrics. |

### Custom Resource Definitions (CRDs)

ADX-Mon defines **9 CRDs** under `adx-mon.azure.com`:
1. `ADXCluster` — ADX cluster connection details
2. `Alerter` — Alerter deployment configuration
3. `AlertRule` — Scheduled KQL alert queries
4. `Collector` — Collector DaemonSet configuration
5. `Function` — ADX stored functions (auto-applied)
6. `Ingestor` — Ingestor StatefulSet configuration
7. `ManagementCommand` — ADX management commands (table policies, etc.)
8. `MetricsExporter` — Export metrics to external systems
9. `SummaryRule` — Scheduled KQL aggregation/ETL jobs

### Authentication
Uses **Azure Workload Identity** (OIDC federation) — no secrets stored. Managed Identities are created and federated with AKS service accounts.

**Sources:** [Official concepts page](https://azure.github.io/adx-mon/concepts/), local `k8s/crds.yaml`, `k8s/collector.yaml`, `k8s/ingestor.yaml`

---

## 3. Metrics Collected

ADX-Mon scrapes **Prometheus-compatible endpoints** and stores each metric name as its own table in the ADX `Metrics` database (hundreds of auto-created tables; the exact count depends on what your cluster workloads expose). Metric names are transformed from `snake_case` to `TitleCase` (e.g., `container_cpu_usage_seconds_total` → `ContainerCpuUsageSecondsTotal`).

### Default Scrape Targets

| Source | Endpoint | Metrics |
|--------|----------|---------|
| **cAdvisor** (container metrics) | `kubelet:10250/metrics/cadvisor` | Container CPU, memory, network, filesystem |
| **Kubelet resource metrics** | `kubelet:10250/metrics/resource` | Node-level CPU and memory summaries |
| **kube-state-metrics** | Annotation-discovered | Pod phase, deployment replicas, node conditions, job status, etc. |
| **kube-apiserver** | `kubernetes.default.svc/metrics` | API server request rates, latencies, etcd cache stats |
| **Any annotated pod** | Pods with `adx-mon/scrape: "true"` | Application-specific Prometheus metrics |
| **Prometheus remote write** | Collector `:3100/receive` | Metrics pushed by any app using remote write protocol |

### Coverage vs Managed Prometheus

| Metric Source | ADX-Mon | Managed Prometheus Default |
|--------------|:-------:|:--------------------------:|
| cAdvisor (container metrics) | ✅ | ✅ |
| Kubelet resource metrics | ✅ | ✅ |
| kube-apiserver | ✅ | ✅ |
| kube-state-metrics | ✅ | ✅ |
| Pod/application metrics | ✅ (annotation) | ✅ (custom scrape config / pod monitors) |
| node-exporter | ❌ (not deployed by default) | ✅ |
| CoreDNS | ❌ (not scraped by default) | ❌ (disabled by default; can be enabled) |

> **Note:** The gaps are **configuration gaps, not capability gaps.** ADX-Mon can scrape any Prometheus endpoint. Deploy node-exporter with `adx-mon/scrape: "true"` annotation, or add static scrape targets in `collector-config` TOML.

### Metric Schema in ADX

Each metric table has a consistent schema:
- `Timestamp` (datetime)
- `SeriesId` (long) — hash of the label set
- `Labels` (dynamic) — all Prometheus labels as a JSON bag
- `Value` (real) — the metric value
- Lifted columns: `Pod`, `Namespace`, `Container`, `host`, `cluster` (configurable via `lift-labels`)

### Counter Handling

ADX-Mon provides a `prom_delta()` function for counter metrics:
```kusto
ContainerCpuUsageSecondsTotal
| where Timestamp > ago(10m)
| invoke prom_delta()
| summarize avg(Value) by Namespace, bin(Timestamp, 1m)
```

**Sources:** [Quick-start guide](https://azure.github.io/adx-mon/quick-start/), local `k8s/collector.yaml`, local `README.md`

---

## 4. Logs Collection

**Yes, ADX-Mon collects logs.** Logs are stored in the ADX `Logs` database.

### Log Sources

| Log Type | How Collected | ADX Table |
|----------|--------------|-----------|
| **Kubelet journal** | `host-log` config → systemd journal filter `_SYSTEMD_UNIT=kubelet.service` | `Kubelet` |
| **adx-mon components** | Pod annotation `adx-mon/log-destination` | `Ingestor`, `Collector` |
| **Application logs** | Pod annotation on your workloads | Any custom table (e.g., `MyAppTable`) |

### How to Enable Log Collection

Annotate your pods:
```yaml
annotations:
  adx-mon/log-destination: "Logs:MyAppTable"   # database:table
  adx-mon/log-parsers: json                     # optional: json, plaintext (default)
```

### Log Ingestion Protocols
- **Container stdout/stderr** — discovered by annotation
- **OTLP logs** — via `otel-log` config section
- **Host/journal logs** — via `host-log` config section with systemd journal matching

### Querying Logs
```kusto
Kubelet
| where Timestamp > ago(1h)
| where Body.message contains "Syncloop ADD"
| summarize count() by bin(Timestamp, 15m), Host=tostring(Resource.host)
```

**Sources:** [Quick-start guide](https://azure.github.io/adx-mon/quick-start/), local `k8s/collector.yaml`

---

## 5. Storage Backend: ADX/Kusto vs Azure Monitor Workspace

### How ADX is Used

- **Two databases created:** `Metrics` and `Logs`
- Each Prometheus metric name becomes its own table in `Metrics` (hundreds of auto-created tables)
- Logs go to named tables in `Logs` database
- Ingestor uses the **Kusto ingestion API** to upload compressed batches
- Tables and ingestion mappings are **auto-managed** by the Ingestor
- Ingestion batching policies are tunable per-database or per-table

### Advantages of ADX/Kusto over Azure Monitor Workspace

| Feature | ADX (adx-mon) | Azure Monitor Workspace (Managed Prometheus) |
|---------|:-------------:|:--------------------------------------------:|
| **Cardinality** | Unlimited — ADX handles any cardinality ([confirmed](https://github.com/Azure/adx-mon#features)) | 1M active time series default (can request increase; [service limits](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/service-limits#prometheus-metrics)) |
| **Retention** | Configurable per-table, up to years (hot/cold cache tiering) | 18 months, not configurable, no additional storage cost ([docs](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/azure-monitor-workspace-overview#data-considerations)) |
| **Query language** | KQL — extremely powerful, supports joins, ML functions, time-series analysis | PromQL only (limited joins, no cross-signal queries); 32-day max query window ([limits](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/service-limits#prometheus-metrics)) |
| **Unified telemetry** | Metrics + logs + traces in one store, queryable together | Metrics only; logs require separate Log Analytics workspace |
| **Cost model** | Pay for ADX cluster compute + storage; predictable | Pay per metric sample ingested + query samples processed; storage included for 18 months ([pricing](https://azure.microsoft.com/pricing/details/monitor/)) |
| **Granularity** | Raw data at any scrape interval | Raw samples stored at scrape interval (minimal ingestion profile filters *which* metrics, but does not aggregate) |
| **Alerting** | KQL-based alerts across metrics AND logs together | Prometheus recording/alerting rules (metrics only) |
| **Data ownership** | Full control — your ADX cluster, your data | Microsoft-managed, less control |
| **Visualization** | Grafana, ADX Dashboards, PowerBI, Tableau, Excel | Grafana (with limitations) |
| **Data transformation** | Update policies, SummaryRules, materialized views | Limited |

### Ingestion Latency

- **Metrics:** ~30 seconds batching default (tunable to lower)
- **Logs:** ~5 minutes batching default (tunable)
- Controlled via `ManagementCommand` CRDs that set ADX ingestion batching policies

**Sources:** [ADX overview](https://learn.microsoft.com/en-us/azure/data-explorer/data-explorer-overview), local `README.md`, [Cookbook](https://azure.github.io/adx-mon/cookbook/cookbook/)

---

## 6. Alerting Capabilities

### ADX-Mon Native Alerting

ADX-Mon has a built-in alerting system via the **`AlertRule` CRD**:

```yaml
apiVersion: adx-mon.azure.com/v1
kind: AlertRule
metadata:
  name: pod-restart-alert
  namespace: adx-mon
spec:
  database: Metrics
  interval: 5m              # How often to evaluate
  query: |
    KubeStatePodStatusContainerRestartCount
    | where Timestamp > ago(10m)
    | invoke prom_delta()
    | summarize Restarts=sum(Value) by Namespace=tostring(Labels.namespace), Pod=tostring(Labels.pod)
    | where Restarts > 3
  destination: "adx-mon-alerts"
  autoMitigateAfter: "15m"  # Auto-resolve after 15 min
```

### Key Features
- **Unified alerting** — alert on metrics AND logs in the same query (cross-signal)
- **KQL-powered** — full power of KQL including joins, ML functions, time-series anomaly detection
- **Pluggable alerting provider API** — customizable notification integrations
- **Auto-mitigation** — alerts can auto-resolve after a configurable period
- **Kubernetes-native** — alert rules are CRDs managed via kubectl/GitOps

### Comparison: ADX-Mon Alerting vs Prometheus Alerting

| Feature | ADX-Mon (KQL Alerts) | Prometheus Alerting (AlertManager) |
|---------|:--------------------:|:----------------------------------:|
| Query language | KQL (joins, ML, cross-signal) | PromQL (metrics only) |
| Cross-signal alerts | ✅ Metrics + logs in one query | ❌ Metrics only |
| Anomaly detection | ✅ Built-in KQL functions (`series_decompose_anomalies`) | ❌ Manual thresholds |
| Cardinality handling | ✅ No limits | ⚠️ High cardinality can slow evaluation |
| Evaluation interval | Configurable per rule | Configurable per rule |
| Notification routing | Pluggable provider API | AlertManager routes |
| GitOps friendly | ✅ Kubernetes CRDs | ✅ ConfigMaps/CRDs |
| Recording rules equivalent | ✅ SummaryRules CRD | ✅ Recording rules |
| Testing locally | ✅ `go run cmd/alerter` against live ADX | ✅ `promtool` |

**Sources:** Local `k8s/sample-alertrule.yaml`, [GitHub README](https://github.com/Azure/adx-mon), [Official concepts](https://azure.github.io/adx-mon/concepts/)

---

## 7. Grafana Integration

### Yes — Full Grafana Support

ADX-Mon/Kusto integrates natively with Grafana via the **Azure Data Explorer datasource plugin**.

### Setup Options

1. **Azure Managed Grafana (recommended):**
   - Deploy via the adx-mon quick-start script or Bicep (as in this repo)
   - ADX datasource is auto-configured via deployment scripts
   - Users get Grafana Admin access automatically

2. **Self-hosted Grafana:**
   - Install the [Azure Data Explorer plugin](https://grafana.com/grafana/plugins/grafana-azure-data-explorer-datasource/)
   - Configure with ADX cluster URI, service principal or managed identity
   - Write KQL queries directly in panels

### Pre-built Dashboards

The adx-mon **quick-start script** (not the Bicep deployment in this repo) can optionally import pre-built dashboards including:
- **API Server** — kube-apiserver request rates and latencies
- **Cluster Info** — overall cluster health
- **Metrics Stats** — ingestion rates and cardinality
- **Namespaces** — per-namespace resource usage
- **Pods** — per-pod CPU, memory, restarts

> ⚠️ **Our Bicep deployment does NOT include these dashboards.** It configures the ADX datasource in Grafana but ships no dashboards. To get these, either run the quick-start script's dashboard import or recreate them manually.

Source: [Quick-start — Setup Dashboards](https://azure.github.io/adx-mon/quick-start/#setup-dashboards)

### Query Optimization in Grafana
- **Results caching** — reduce load on ADX cluster
- **Weak consistency** — trade 1-2 min staleness for faster rendering
- Both configured in the Grafana ADX datasource settings

### How to Query in Grafana
```kusto
// In a Grafana panel using ADX datasource:
ContainerMemoryWorkingSetBytes
| where Timestamp > $__timeFrom and Timestamp < $__timeTo
| invoke prom_delta()
| summarize avg(Value) by Namespace, bin(Timestamp, $__interval)
```

> **Note:** Only `prom_delta()` is deployed in this repo (see `modules/adx.bicep`). The adx-mon quick-start script may deploy additional helper functions.

**Sources:** [Grafana + ADX docs](https://learn.microsoft.com/en-us/azure/data-explorer/grafana), [Quick-start](https://azure.github.io/adx-mon/quick-start/), local `README.md`

---

## 8. Multi-Cluster / Fleet Monitoring

### Architecture for Multi-Cluster

ADX-Mon supports fleet monitoring by deploying Collectors and Ingestors **per-cluster** while pointing them all to the **same ADX cluster**:

```
 AKS Cluster A                    AKS Cluster B                    AKS Cluster C
┌──────────────────┐            ┌──────────────────┐            ┌──────────────────┐
│ Collector → Ingestor ─┐       │ Collector → Ingestor ─┐       │ Collector → Ingestor ─┐
└──────────────────┘    │       └──────────────────┘    │       └──────────────────┘    │
                        ▼                               ▼                               ▼
                    ┌──────────────────────────────────────────────────────────────┐
                    │              Azure Data Explorer (shared)                     │
                    │   Metrics DB: all clusters' metrics in same tables           │
                    │   Logs DB: all clusters' logs in same tables                 │
                    └──────────────────────────────────────────────────────────────┘
```

### How It Works

1. **Cluster label injection:** Each Collector is configured with `[add-labels] cluster = '<cluster-name>'` in its TOML config. This adds a `cluster` label to every metric and log.

2. **Label lifting:** The `cluster` label is lifted to a top-level ADX column for efficient filtering:
   ```toml
   lift-labels = [
     { name = 'cluster' },
     { name = 'host' },
   ]
   ```

3. **Shared ADX cluster:** All Ingestors point to the same `--metrics-kusto-endpoints` and `--logs-kusto-endpoints`. Data from all clusters lands in the same tables.

4. **Cluster label substitution in SummaryRules:** Use `_<label>` placeholders for environment-specific rules:
   ```yaml
   spec:
     body: |
       Metrics
       | where Labels.cluster == "_cluster"
       | where Timestamp between (_startTime .. _endTime)
       ...
   ```
   Deploy with: `--cluster-labels=cluster=prod-east`

### Querying Across Clusters
```kusto
// Compare CPU usage across all clusters
ContainerCpuUsageSecondsTotal
| where Timestamp > ago(1h)
| invoke prom_delta()
| summarize avg(Value) by Cluster=tostring(Labels.cluster), bin(Timestamp, 5m)
| render timechart
```

### Fleet Advantages over Self-Hosted Prometheus
- **Single query plane** — KQL across all clusters' data in one ADX database
- **No federation needed** — unlike *self-hosted* Prometheus which requires Thanos/Cortex/federation for multi-cluster (note: Azure Managed Prometheus also centralizes multi-cluster data via Azure Monitor Workspace, so this advantage applies primarily vs. self-hosted)
- **Consistent schema** — same tables, same columns, just filter by cluster label
- **Cost efficient** — one ADX cluster serves the entire fleet
- **Cross-cluster correlation** — join metrics from different clusters in a single KQL query

**Sources:** [Concepts](https://azure.github.io/adx-mon/concepts/), [Cookbook](https://azure.github.io/adx-mon/cookbook/cookbook/), local `k8s/collector.yaml`

---

## Gaps

This section identifies areas where our adx-mon deployment does **not** provide equivalent coverage to the broader Azure monitoring ecosystem.

### 1. Control Plane / Audit Logs

AKS **Diagnostic Settings** can stream control plane logs (kube-apiserver, kube-audit, kube-scheduler, kube-controller-manager, cloud-controller-manager, etc.) to Log Analytics or a Storage Account. These are **Azure resource-level logs** emitted by the managed control plane — adx-mon has no mechanism to capture them because they are not pod logs.

**Impact:** We have no audit trail of Kubernetes API operations (who created/deleted resources, RBAC changes, etc.) unless Diagnostic Settings are enabled separately.

**Reference:** [AKS Diagnostic Settings](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#resource-logs)

### 2. Kubernetes Events

AKS with Container Insights captures `KubeEvents` (pod scheduling failures, image pull errors, OOM kills, etc.) into a Log Analytics table. adx-mon does **not** collect Kubernetes events — the collector only handles Prometheus metrics, pod stdout/stderr logs, and host journal logs.

**Impact:** Cluster operators lose visibility into scheduling failures, eviction events, and other control-plane-generated events.

### 3. Node-Level Hardware Metrics (node-exporter)

Our deployment does **not** deploy `node-exporter`. While cAdvisor and kubelet resource metrics cover container-level CPU/memory/disk, node-exporter provides host-level metrics: detailed filesystem usage, network interface statistics, hardware temperatures, and system load averages.

**Impact:** Node-level disk pressure, network saturation, and hardware issues are harder to detect without node-exporter. This is a **deployment gap**, not a platform limitation — adx-mon can scrape node-exporter if deployed.

### 4. Geneva / Microsoft-Internal Telemetry

[Geneva](https://eng.ms/docs/products/geneva/) (also known as MDM, Jarvis, GCS) is Microsoft's **internal** telemetry pipeline. It is the underlying system for Azure Monitor but is **not customer-facing**. Customers interact with it indirectly via:

- **Azure Monitor Agent (AMA)** — the external-facing agent that collects and ships data
- **Data Collection Rules (DCRs)** — configure what AMA collects
- **Log Analytics / Azure Monitor Workspace** — where data lands

**Our position:** We don't need to integrate with Geneva directly. It's an internal implementation detail. However, any Azure-native monitoring feature (Recommended Alerts, Workbooks, Cost Analysis integration) ultimately runs on Geneva — which means skipping Azure Monitor entirely means skipping those integrated features.

### 5. Application Insights / Distributed Tracing

Azure Application Insights provides end-to-end distributed tracing, application performance monitoring (APM), live metrics stream, and application map visualization. adx-mon's platform supports OTLP trace ingestion, but:

- **We do not deploy trace collection** in this repo
- There is no equivalent to Application Insights' automatic dependency tracking, exception telemetry, or application map
- Applications would need to emit OTLP traces explicitly via OpenTelemetry SDK

**Impact:** No application-level performance monitoring, no distributed traces, no automatic dependency tracking.

### 6. Azure Action Groups / Native Alert Integration

Azure Monitor alerts integrate natively with **Action Groups** (email, SMS, webhook, Logic Apps, ITSM, Azure Functions). adx-mon's Alerter component (not deployed here) fires alerts via its own mechanism — there is no native integration with Azure Action Groups.

**Impact:** Alert routing, on-call escalation, and ticketing integration must be built separately if using adx-mon alerting.

### 7. Container Insights Broad Log Coverage

Container Insights (with AMA and DCR) captures **all container stdout/stderr** by default from every pod in the cluster. adx-mon requires explicit pod annotations (`adx-mon/log-destination`) to opt pods into log collection. Without annotations, pod logs are not collected.

**Impact:** Any new workload deployed without the annotation will be invisible in logs until annotated. This is by design (reduces noise/cost) but means new deployments can be missed.

### 8. Pre-built Dashboards and Workbooks

Azure Monitor provides a rich set of [pre-built workbooks](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#workbooks) for AKS: cluster health, node health, deployment health, GPU monitoring, and more. Managed Prometheus adds 12+ pre-built Grafana dashboards.

Our adx-mon Bicep deployment creates **no dashboards**. The quick-start script can import some, but we don't use it.

**Impact:** Every dashboard must be built from scratch in Grafana using KQL queries against ADX.

### 9. Microsoft Defender for Cloud

Defender for Containers provides runtime threat detection, vulnerability scanning, and compliance posture. It operates independently of the monitoring stack but integrates with Azure Monitor for alerting. adx-mon does not interact with Defender in any way.

**Impact:** Security monitoring is a separate concern. This is not a gap in adx-mon per se, but worth noting that switching away from Azure Monitor does not affect Defender capabilities — they remain available regardless.

### Summary of Gaps

| Gap | Severity | Mitigation |
|-----|----------|------------|
| Control plane / audit logs | 🔴 High | Enable AKS Diagnostic Settings alongside adx-mon |
| Kubernetes events | 🟡 Medium | Could deploy a K8s event exporter that exposes events as metrics or logs |
| Node-exporter | 🟡 Medium | Deploy node-exporter DaemonSet; adx-mon will auto-scrape it |
| Application Insights / tracing | 🟡 Medium | Enable OTLP trace collection in collector config; or use App Insights separately |
| Action Groups | 🟡 Medium | Deploy Alerter + build webhook bridge; or use ADX alerts with Logic Apps |
| Container log opt-in | 🟢 Low | Document annotation requirement; add to deployment templates |
| Pre-built dashboards | 🟢 Low | Build custom Grafana dashboards; or import from quick-start |
| Geneva | ℹ️ Info | No action needed; it's an internal implementation detail |
| Defender for Cloud | ℹ️ Info | Independent of monitoring stack; no gap |

---

## Summary

| Capability | ADX-Mon Approach |
|-----------|-----------------|
| **Metrics** | Prometheus scraping → ADX (each metric = own table) |
| **Logs** | Pod annotations + host journal → ADX |
| **Traces** | OTLP → ADX *(platform capability; not deployed here)* |
| **Storage** | Azure Data Explorer (KQL) |
| **Alerting** | AlertRule CRD → KQL queries on schedule *(Alerter not deployed here)* |
| **Visualization** | Grafana (ADX plugin), ADX Dashboards, PowerBI |
| **Multi-cluster** | Shared ADX cluster + cluster labels |
| **Auth** | Azure Workload Identity (no secrets) |
| **Configuration** | Kubernetes CRDs + TOML config |
| **Open Source** | [github.com/Azure/adx-mon](https://github.com/Azure/adx-mon) (Microsoft CLA) |
