targetScope = 'subscription'

extension microsoftGraphV1

// ---------- Parameters ----------

@description('Name of the resource group.')
param resourceGroupName string = 'rg-adx-mon'

@description('Azure region for all resources.')
param location string = 'eastus2'

@description('Name of the AKS managed cluster.')
param aksClusterName string = 'aks-adx-mon'

@description('Globally unique name for the ADX cluster (lowercase alphanumeric only).')
@maxLength(22)
param adxClusterName string = 'adxmon${uniqueString(subscription().id)}'

@description('Name of the Grafana workspace.')
param grafanaName string = 'grafana-adx-mon'

@description('Name of the adx-mon workload identity.')
param adxMonIdentityName string = 'id-adx-mon'

@description('Name of the deployer managed identity for deployment scripts.')
param deployerIdentityName string = 'id-adx-mon-deployer'

@description('Name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'law-adx-mon'

@description('Name of the Azure Monitor Workspace (Managed Prometheus).')
param azureMonitorWorkspaceName string = 'amw-adx-mon'

@description('Name of the Data Collection Endpoint (Managed Prometheus).')
param managedPrometheusDataCollectionEndpointName string = 'dce-adx-mon'

@description('Name of the Data Collection Rule for Prometheus metrics.')
param managedPrometheusDataCollectionRuleName string = 'dcr-adx-mon-prometheus'

@description('Name of the Data Collection Endpoint (Container Insights).')
param containerInsightsDataCollectionEndpointName string = 'dce-adx-mon-ci'

@description('Name of the Data Collection Rule (Container Insights).')
param containerInsightsDataCollectionRuleName string = 'dcr-adx-mon-ci'

@description('VM size for the AKS system node pool.')
param nodeVmSize string = 'Standard_D4s_v3'

@description('Number of nodes in the AKS system node pool.')
param nodeCount int = 2

@description('SKU name for the ADX cluster.')
param adxSkuName string = 'Standard_E2ads_v5'

@description('SKU capacity (instance count) for the ADX cluster.')
param adxSkuCapacity int = 2

@description('User principal names (UPN emails) to grant ADX Viewer and Grafana Admin access. For TME tenant, use alias@tme01.onmicrosoft.com.')
param userPrincipalNames string[] = []

@description('Set to any unique value (e.g. a timestamp) to force deployment scripts to re-execute. Leave empty for normal behavior — scripts only rerun when their inputs change.')
param forceScriptRerun string = ''

@description('Enable Managed Prometheus for AKS metrics collection.')
param enableManagedPrometheus bool = true

@description('Enable Azure Monitor recommended AKS metric alerts.')
param enableRecommendedMetricAlerts bool = true

@description('Resource ID of the Azure Monitor Action Group used by alert rules.')
param actionGroupResourceId string

@description('Alert owner/contact identifiers used as alert metadata (for example: aliases).')
param alertOwnerIds string[]

@description('Enable full Prometheus metrics profile and pod-annotation scraping.')
param enableFullPrometheusMetrics bool = true

@description('Enable AKS control-plane diagnostic settings (logs to Log Analytics).')
param enableDiagnosticSettings bool = true

@description('Enable Container Insights for AKS log collection (ContainerLogV2, KubePodInventory, KubeEvents).')
param enableContainerInsights bool = true

@description('Grafana dashboard definitions to provision. Each entry needs a title and a definition (JSON model object).')
param dashboardDefinitions array = []

// ---------- Resolve UPN emails → object IDs via Microsoft Graph ----------

resource users 'Microsoft.Graph/users@v1.0' existing = [for upn in userPrincipalNames: {
  userPrincipalName: upn
}]

// Load demo-app dashboard JSON
var demoAppDashboardJson = loadJsonContent('dashboards/demo-app.json')
var defaultDashboards = [
  {
    title: 'Demo App - adx-mon'
    definition: demoAppDashboardJson
  }
]

// Combine default dashboards with user-provided ones
var allDashboards = concat(defaultDashboards, dashboardDefinitions)

// ---------- Resource Group ----------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

// ---------- AKS ----------

module aks 'modules/aks.bicep' = {
  scope: rg
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    nodeVmSize: nodeVmSize
    nodeCount: nodeCount
  }
}

// ---------- ADX (parallel with AKS) ----------

module adx 'modules/adx.bicep' = {
  scope: rg
  name: 'adx-deployment'
  params: {
    clusterName: adxClusterName
    location: location
    skuName: adxSkuName
    skuCapacity: adxSkuCapacity
  }
}

// ---------- Identity (needs AKS OIDC URL) ----------

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity-deployment'
  params: {
    adxMonIdentityName: adxMonIdentityName
    deployerIdentityName: deployerIdentityName
    location: location
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    aksClusterName: aks.outputs.aksName
  }
}

// ---------- Grafana (parallel, with user admin access) ----------

module grafana 'modules/grafana.bicep' = {
  scope: rg
  name: 'grafana-deployment'
  params: {
    grafanaName: grafanaName
    location: location
  }
}

// ---------- Managed Prometheus (optional, needs AKS and Grafana) ----------

module managedPrometheus 'modules/managed-prometheus.bicep' = if (enableManagedPrometheus) {
  scope: rg
  name: 'managed-prometheus-deployment'
  params: {
    location: location
    aksClusterName: aks.outputs.aksName
    azureMonitorWorkspaceName: azureMonitorWorkspaceName
    dataCollectionEndpointName: managedPrometheusDataCollectionEndpointName
    dataCollectionRuleName: managedPrometheusDataCollectionRuleName
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    grafanaName: grafana.outputs.grafanaName
  }
}

// ---------- Prometheus Recording Rules (optional, needs AKS and Managed Prometheus) ----------

module prometheusRules 'modules/prometheus-rules.bicep' = if (enableManagedPrometheus) {
  scope: rg
  name: 'prometheus-rules-deployment'
  params: {
    location: location
    #disable-next-line BCP318
    azureMonitorWorkspaceId: managedPrometheus.outputs.azureMonitorWorkspaceId
    aksClusterId: aks.outputs.aksId
    aksClusterName: aksClusterName
  }
}

// ---------- Recommended Metric Alerts (optional, needs AKS and Managed Prometheus) ----------

module recommendedMetricAlerts 'modules/recommended-metric-alerts.bicep' = if (enableManagedPrometheus && enableRecommendedMetricAlerts) {
  scope: rg
  name: 'recommended-metric-alerts-deployment'
  params: {
    location: location
    aksClusterId: aks.outputs.aksId
    #disable-next-line BCP318
    azureMonitorWorkspaceId: managedPrometheus.outputs.azureMonitorWorkspaceId
    actionGroupResourceId: actionGroupResourceId
  }
}

// ---------- Simple Custom Prometheus Alert Demo ----------

module simplePrometheusAlert 'modules/simple-prometheus-alert.bicep' = if (enableManagedPrometheus && enableRecommendedMetricAlerts) {
  scope: rg
  name: 'simple-prometheus-alert-deployment'
  params: {
    location: location
    aksClusterId: aks.outputs.aksId
    aksClusterName: aksClusterName
    #disable-next-line BCP318
    azureMonitorWorkspaceId: managedPrometheus.outputs.azureMonitorWorkspaceId
    actionGroupResourceId: actionGroupResourceId
    alertOwnerIds: alertOwnerIds
  }
  dependsOn: [
    recommendedMetricAlerts
  ]
}

// ---------- Log Analytics Workspace (shared by Diagnostic Settings and Container Insights) ----------

var needsLaw = enableDiagnosticSettings || enableContainerInsights

module logAnalytics 'modules/log-analytics.bicep' = if (needsLaw) {
  scope: rg
  name: 'log-analytics-deployment'
  params: {
    location: location
    workspaceName: logAnalyticsWorkspaceName
  }
}

// ---------- Diagnostic Settings (optional, needs AKS + LAW) ----------

module diagnosticSettings 'modules/diagnostic-settings.bicep' = if (enableDiagnosticSettings) {
  scope: rg
  name: 'diagnostic-settings-deployment'
  params: {
    aksClusterName: aks.outputs.aksName
    #disable-next-line BCP321 BCP318
    logAnalyticsWorkspaceId: needsLaw ? logAnalytics.outputs.workspaceId : ''
  }
}

// ---------- Container Insights (optional, needs AKS + LAW + Grafana; after MP to avoid AKS conflict) ----------

module containerInsights 'modules/container-insights.bicep' = if (enableContainerInsights) {
  scope: rg
  name: 'container-insights-deployment'
  params: {
    aksClusterName: aks.outputs.aksName
    location: location
    dataCollectionEndpointName: containerInsightsDataCollectionEndpointName
    dataCollectionRuleName: containerInsightsDataCollectionRuleName
    #disable-next-line BCP321 BCP318
    logAnalyticsWorkspaceId: needsLaw ? logAnalytics.outputs.workspaceId : ''
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    #disable-next-line BCP318
    existingDataCollectionEndpointId: enableManagedPrometheus ? managedPrometheus.outputs.dataCollectionEndpointId : ''
  }
}

// ---------- Role Assignments (needs ADX, identity, grafana) ----------

module roleAssignments 'modules/role-assignments.bicep' = {
  scope: rg
  name: 'role-assignments-deployment'
  params: {
    adxClusterName: adx.outputs.adxName
    adxMonAppId: identity.outputs.adxMonIdentityClientId
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    grafanaName: grafana.outputs.grafanaName
    viewerPrincipalIds: [for (upn, i) in userPrincipalNames: users[i].id]
  }
}

// ---------- K8s Workloads (needs AKS, ADX, identity, roleAssignments) ----------

module k8sWorkloads 'modules/k8s-workloads.bicep' = {
  scope: rg
  name: 'k8s-workloads-deployment'
  params: {
    location: location
    aksClusterName: aks.outputs.aksName
    adxUri: adx.outputs.adxUri
    adxMonClientId: identity.outputs.adxMonIdentityClientId
    clusterName: aksClusterName
    region: location
    deployerIdentityId: identity.outputs.deployerIdentityId
    forceScriptRerun: forceScriptRerun
    enableFullPrometheusMetrics: enableFullPrometheusMetrics
  }
}

// ---------- Grafana Config — datasource + optional dashboards ----------

module grafanaConfig 'modules/grafana-config.bicep' = {
  scope: rg
  name: 'grafana-config-deployment'
  params: {
    location: location
    grafanaName: grafana.outputs.grafanaName
    adxUri: adx.outputs.adxUri
    adxClusterName: adx.outputs.adxName
    deployerIdentityId: identity.outputs.deployerIdentityId
    deployerPrincipalId: identity.outputs.deployerPrincipalId
    forceScriptRerun: forceScriptRerun
    dashboardDefinitions: allDashboards
  }
}

// ---------- Outputs ----------

output aksClusterName string = aks.outputs.aksName
output adxClusterUri string = adx.outputs.adxUri
output adxWebExplorerUrl string = 'https://dataexplorer.azure.com/clusters/${replace(adx.outputs.adxUri, 'https://', '')}/databases/Metrics'
output adxLogsExplorerUrl string = 'https://dataexplorer.azure.com/clusters/${replace(adx.outputs.adxUri, 'https://', '')}/databases/Logs'
output grafanaEndpoint string = grafana.outputs.grafanaEndpoint
output resourceGroupName string = rg.name
#disable-next-line BCP318
output azureMonitorWorkspaceId string = enableManagedPrometheus ? managedPrometheus.outputs.azureMonitorWorkspaceId : ''
#disable-next-line BCP318
output logAnalyticsPortalUrl string = needsLaw ? 'https://portal.azure.com/#@${tenant().tenantId}/resource${logAnalytics.outputs.workspaceId}/logs' : ''
#disable-next-line BCP318
output recommendedMetricAlertRuleGroupNames array = (enableManagedPrometheus && enableRecommendedMetricAlerts) ? recommendedMetricAlerts.outputs.recommendedAlertRuleGroupNames : []
#disable-next-line BCP318
output demoCustomAlertRuleGroupName string = (enableManagedPrometheus && enableRecommendedMetricAlerts) ? simplePrometheusAlert.outputs.customAlertRuleGroupName : ''
output alertLocation string = location
output azureMonitorAlertPortalUrls array = (enableManagedPrometheus && enableRecommendedMetricAlerts) ? [
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/KubernetesAlert-RecommendedMetricAlerts${aksClusterName}-Cluster-level/overview'
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/KubernetesAlert-RecommendedMetricAlerts${aksClusterName}-Node-level/overview'
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/KubernetesAlert-RecommendedMetricAlerts${aksClusterName}-Pod-level/overview'
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/DemoCustomAlertsRuleGroup-${aksClusterName}/overview'
] : []
output adxMonSampleAlertRuleFile string = 'k8s/sample-alertrule.yaml'
output adxMonSampleAlertKubectlCommand string = 'kubectl -n adx-mon get alertrule pod-restart-alert -o yaml'
