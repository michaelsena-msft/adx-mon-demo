// ---------------------------------------------------------------------------
// Prometheus Recording Rules for Azure Managed Prometheus
// ---------------------------------------------------------------------------
//
// WHY THIS MODULE EXISTS:
//
// When you enable Azure Monitor metrics on AKS via the CLI command
// `az aks update --enable-azure-monitor-metrics`, Azure automatically creates
// Prometheus recording rule groups as a separate ARM deployment behind the
// scenes. These recording rules pre-compute aggregated metrics (e.g.
// node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate)
// that the auto-provisioned Kubernetes Compute dashboards in Managed Grafana
// depend on. Without them, those dashboards show "No data".
//
// Our Bicep creates the Azure Monitor Workspace, Data Collection Endpoint,
// Data Collection Rule, and DCRAs directly — bypassing that CLI. This gives
// us full control over the monitoring pipeline, but it means the recording
// rules are NOT auto-created. We must declare them ourselves.
//
// THE RULES ARE NOT CUSTOM. They are standard open-source Prometheus mixins
// used by every Azure Managed Prometheus deployment. Microsoft documents each
// rule at:
//   https://learn.microsoft.com/azure/azure-monitor/containers/prometheus-metrics-scrape-default#recording-rules
//
// The source mixin definitions are published at:
//   https://aka.ms/azureprometheus-mixins
//
// The JSON files in ../rules/ were exported from a working CLI-provisioned
// cluster in the same subscription and contain no custom modifications.
// ---------------------------------------------------------------------------

@description('Azure region for the rule groups.')
param location string

@description('Resource ID of the Azure Monitor Workspace.')
param azureMonitorWorkspaceId string

@description('Resource ID of the AKS cluster.')
param aksClusterId string

@description('Name of the AKS cluster (used in rule group naming).')
param aksClusterName string

var nodeRules = loadJsonContent('../rules/node-recording-rules.json')
var kubernetesRules = loadJsonContent('../rules/kubernetes-recording-rules.json')
var uxRules = loadJsonContent('../rules/ux-recording-rules.json')

resource nodeRecordingRules 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: 'NodeRecordingRulesRuleGroup-${aksClusterName}'
  location: location
  properties: {
    scopes: [azureMonitorWorkspaceId, aksClusterId]
    clusterName: aksClusterName
    interval: 'PT1M'
    rules: nodeRules
  }
}

resource kubernetesRecordingRules 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: 'KubernetesRecordingRulesRuleGroup-${aksClusterName}'
  location: location
  properties: {
    scopes: [azureMonitorWorkspaceId, aksClusterId]
    clusterName: aksClusterName
    interval: 'PT1M'
    rules: kubernetesRules
  }
}

resource uxRecordingRules 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: 'UXRecordingRulesRuleGroup-${aksClusterName}'
  location: location
  properties: {
    scopes: [azureMonitorWorkspaceId, aksClusterId]
    clusterName: aksClusterName
    interval: 'PT1M'
    rules: uxRules
  }
}
