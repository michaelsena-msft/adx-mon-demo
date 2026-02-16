targetScope = 'resourceGroup'

extension microsoftGraphV1

type DashboardDefinition = {
  title: string
  definition: object
}

type AlertEmailReceiver = {
  name: string
  emailAddress: string
}

@description('Resource ID of the existing AKS cluster in this resource group.')
param aksClusterResourceId string

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Globally unique name for the ADX cluster (lowercase alphanumeric only).')
@maxLength(22)
param adxClusterName string = 'adxmon${uniqueString(subscription().id)}'

@description('Name of the Grafana workspace.')
param grafanaName string = 'grafana-adx-mon'

@description('Name of the adx-mon workload identity.')
param adxMonIdentityName string = 'id-adx-mon'

@description('Name of the AKS script deployer managed identity for deployment scripts.')
param aksScriptDeployerIdentityName string = 'id-adx-mon-aks-deployer'

@description('Name of the Grafana config deployer managed identity for deployment scripts.')
param grafanaConfigDeployerIdentityName string = 'id-adx-mon-grafana-deployer'

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

@description('Name of the Azure Monitor Action Group used by alert rules.')
param actionGroupName string = 'ag-adx-mon'

@description('Email receivers for the Action Group used by alert rules.')
param alertEmailReceivers AlertEmailReceiver[]

@description('Alert owner/contact identifiers used as alert metadata (for example: aliases).')
param alertOwnerIds string[]

@description('Enable AKS control-plane diagnostic settings (logs to Log Analytics).')
param enableDiagnosticSettings bool = true

@description('Enable Container Insights for AKS log collection (ContainerLogV2, KubePodInventory, KubeEvents).')
param enableContainerInsights bool = true

@description('Additional Grafana dashboard definitions to provision. Each entry needs a title and a definition (JSON model object).')
param dashboardDefinitions DashboardDefinition[] = []

var aksClusterName = last(split(aksClusterResourceId, '/'))

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

resource users 'Microsoft.Graph/users@v1.0' existing = [for upn in userPrincipalNames: {
  userPrincipalName: upn
}]

var demoAppDashboardJson = loadJsonContent('dashboards/demo-app.json')
var defaultDashboards = [
  {
    title: 'Demo App - adx-mon'
    definition: demoAppDashboardJson
  }
]

var allDashboards = concat(defaultDashboards, dashboardDefinitions)
var azureMonitorWorkspaceResourceId = resourceId('Microsoft.Monitor/accounts', azureMonitorWorkspaceName)
var managedPrometheusDataCollectionEndpointResourceId = resourceId('Microsoft.Insights/dataCollectionEndpoints', managedPrometheusDataCollectionEndpointName)
var logAnalyticsWorkspaceResourceId = resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceName)
var alertActionGroupResourceId = resourceId('Microsoft.Insights/actionGroups', actionGroupName)
var aksOidcIssuerUrl = aksCluster.properties.oidcIssuerProfile.issuerURL
var needsLaw = enableDiagnosticSettings || enableContainerInsights

module adx 'modules/adx/cluster.bicep' = {
  name: 'adx-deployment'
  params: {
    clusterName: adxClusterName
    location: location
    skuName: adxSkuName
    skuCapacity: adxSkuCapacity
  }
}

module adxIdentity 'modules/adx/identity.bicep' = {
  name: 'adx-identity-deployment'
  params: {
    adxMonIdentityName: adxMonIdentityName
    aksScriptDeployerIdentityName: aksScriptDeployerIdentityName
    location: location
    aksOidcIssuerUrl: aksOidcIssuerUrl
    aksClusterName: aksClusterName
  }
}

module grafana 'modules/grafana.bicep' = {
  name: 'grafana-deployment'
  params: {
    grafanaName: grafanaName
    location: location
  }
}

module grafanaConfigDeployerIdentity 'modules/grafana/config-deployer-identity.bicep' = {
  name: 'grafana-config-deployer-identity-deployment'
  params: {
    grafanaConfigDeployerIdentityName: grafanaConfigDeployerIdentityName
    location: location
  }
}

module managedPrometheus 'modules/azure-monitor/managed-prometheus.bicep' = if (enableManagedPrometheus) {
  name: 'managed-prometheus-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    azureMonitorWorkspaceName: azureMonitorWorkspaceName
    dataCollectionEndpointName: managedPrometheusDataCollectionEndpointName
    dataCollectionRuleName: managedPrometheusDataCollectionRuleName
  }
}

module grafanaBindAmw 'modules/grafana/bind-amw.bicep' = if (enableManagedPrometheus) {
  name: 'grafana-bind-amw-deployment'
  params: {
    location: location
    grafanaName: grafana.outputs.grafanaName
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    azureMonitorWorkspaceName: azureMonitorWorkspaceName
  }
  dependsOn: [
    managedPrometheus
  ]
}

module prometheusRules 'modules/azure-monitor/prometheus-rules.bicep' = if (enableManagedPrometheus) {
  name: 'prometheus-rules-deployment'
  params: {
    location: location
    azureMonitorWorkspaceId: azureMonitorWorkspaceResourceId
    aksClusterId: aksClusterResourceId
    aksClusterName: aksClusterName
  }
  dependsOn: [
    managedPrometheus
  ]
}

module actionGroup 'modules/azure-monitor/action-group.bicep' = if (enableManagedPrometheus) {
  name: 'action-group-deployment'
  params: {
    actionGroupName: actionGroupName
    emailReceivers: alertEmailReceivers
  }
}

module recommendedMetricAlerts 'modules/azure-monitor/recommended-metric-alerts.bicep' = if (enableManagedPrometheus) {
  name: 'recommended-metric-alerts-deployment'
  params: {
    location: location
    aksClusterId: aksClusterResourceId
    azureMonitorWorkspaceId: azureMonitorWorkspaceResourceId
    actionGroupResourceId: alertActionGroupResourceId
  }
  dependsOn: [
    managedPrometheus
    actionGroup
  ]
}

module simplePrometheusAlert 'modules/azure-monitor/simple-prometheus-alert.bicep' = if (enableManagedPrometheus) {
  name: 'simple-prometheus-alert-deployment'
  params: {
    location: location
    aksClusterId: aksClusterResourceId
    aksClusterName: aksClusterName
    azureMonitorWorkspaceId: azureMonitorWorkspaceResourceId
    actionGroupResourceId: alertActionGroupResourceId
    alertOwnerIds: alertOwnerIds
  }
  dependsOn: [
    recommendedMetricAlerts
  ]
}

module logAnalytics 'modules/azure-monitor/log-analytics.bicep' = if (needsLaw) {
  name: 'log-analytics-deployment'
  params: {
    location: location
    workspaceName: logAnalyticsWorkspaceName
  }
}

module diagnosticSettings 'modules/azure-monitor/diagnostic-settings.bicep' = if (enableDiagnosticSettings) {
  name: 'diagnostic-settings-deployment'
  params: {
    aksClusterName: aksClusterName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceResourceId
  }
  dependsOn: [
    logAnalytics
  ]
}

module containerInsightsWithManagedPrometheus 'modules/azure-monitor/container-insights.bicep' = if (enableContainerInsights && enableManagedPrometheus) {
  name: 'container-insights-deployment-mp'
  params: {
    aksClusterName: aksClusterName
    location: location
    dataCollectionEndpointName: containerInsightsDataCollectionEndpointName
    dataCollectionRuleName: containerInsightsDataCollectionRuleName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceResourceId
    existingDataCollectionEndpointId: managedPrometheusDataCollectionEndpointResourceId
  }
  dependsOn: [
    logAnalytics
    managedPrometheus
    diagnosticSettings
  ]
}

module containerInsightsWithoutManagedPrometheus 'modules/azure-monitor/container-insights.bicep' = if (enableContainerInsights && !enableManagedPrometheus) {
  name: 'container-insights-deployment'
  params: {
    aksClusterName: aksClusterName
    location: location
    dataCollectionEndpointName: containerInsightsDataCollectionEndpointName
    dataCollectionRuleName: containerInsightsDataCollectionRuleName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceResourceId
    existingDataCollectionEndpointId: ''
  }
  dependsOn: [
    logAnalytics
    diagnosticSettings
  ]
}

module grafanaBindLaw 'modules/grafana/bind-law.bicep' = if (needsLaw) {
  name: 'grafana-bind-law-deployment'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
  }
  dependsOn: [
    logAnalytics
  ]
}

module adxRbac 'modules/adx/rbac.bicep' = {
  name: 'adx-rbac-deployment'
  params: {
    adxClusterName: adx.outputs.adxName
    adxMonAppId: adxIdentity.outputs.adxMonIdentityClientId
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    viewerPrincipalIds: [for (upn, i) in userPrincipalNames: users[i].id]
  }
}

module grafanaAdminUsers 'modules/grafana/admin-rbac-users.bicep' = {
  name: 'grafana-admin-users-deployment'
  params: {
    grafanaName: grafana.outputs.grafanaName
    adminPrincipalIds: [for (upn, i) in userPrincipalNames: users[i].id]
  }
}

module k8sWorkloads 'modules/adx/workloads.bicep' = {
  name: 'k8s-workloads-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    adxUri: adx.outputs.adxUri
    adxMonClientId: adxIdentity.outputs.adxMonIdentityClientId
    aksScriptDeployerIdentityId: adxIdentity.outputs.aksScriptDeployerIdentityId
    forceScriptRerun: forceScriptRerun
  }
}

module grafanaAdxDatasource 'modules/grafana/bind-adx-datasource.bicep' = {
  name: 'grafana-adx-datasource-deployment'
  params: {
    location: location
    grafanaName: grafana.outputs.grafanaName
    adxUri: adx.outputs.adxUri
    adxClusterName: adx.outputs.adxName
    grafanaConfigDeployerIdentityId: grafanaConfigDeployerIdentity.outputs.grafanaConfigDeployerIdentityId
    grafanaConfigDeployerPrincipalId: grafanaConfigDeployerIdentity.outputs.grafanaConfigDeployerPrincipalId
    forceScriptRerun: forceScriptRerun
    dashboardDefinitions: allDashboards
  }
  dependsOn: [
    adxRbac
    grafanaAdminUsers
  ]
}

output aksClusterName string = aksClusterName
output adxWebExplorerUrl string = 'https://dataexplorer.azure.com/clusters/${replace(adx.outputs.adxUri, 'https://', '')}'
output grafanaEndpoint string = grafana.outputs.grafanaEndpoint
output logAnalyticsPortalUrl string = needsLaw ? 'https://portal.azure.com/#@${tenant().tenantId}/resource${logAnalyticsWorkspaceResourceId}/logs' : ''
output azureMonitorAlertPortalUrls array = enableManagedPrometheus ? [
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/KubernetesAlert-RecommendedMetricAlerts${aksClusterName}-Cluster-level/overview'
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/KubernetesAlert-RecommendedMetricAlerts${aksClusterName}-Node-level/overview'
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/KubernetesAlert-RecommendedMetricAlerts${aksClusterName}-Pod-level/overview'
  'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.AlertsManagement/prometheusRuleGroups/DemoCustomAlertsRuleGroup-${aksClusterName}/overview'
] : []
