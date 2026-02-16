targetScope = 'subscription'

type DashboardDefinition = {
  title: string
  definition: object
}

type AlertEmailReceiver = {
  name: string
  emailAddress: string
}

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

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

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

var aksResourceId = resourceId(subscription().subscriptionId, resourceGroupName, 'Microsoft.ContainerService/managedClusters', aksClusterName)

module observability 'observability.bicep' = {
  scope: rg
  name: 'observability-deployment'
  params: {
    location: location
    aksClusterResourceId: aksResourceId
    adxClusterName: adxClusterName
    grafanaName: grafanaName
    adxMonIdentityName: adxMonIdentityName
    aksScriptDeployerIdentityName: aksScriptDeployerIdentityName
    grafanaConfigDeployerIdentityName: grafanaConfigDeployerIdentityName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    azureMonitorWorkspaceName: azureMonitorWorkspaceName
    managedPrometheusDataCollectionEndpointName: managedPrometheusDataCollectionEndpointName
    managedPrometheusDataCollectionRuleName: managedPrometheusDataCollectionRuleName
    containerInsightsDataCollectionEndpointName: containerInsightsDataCollectionEndpointName
    containerInsightsDataCollectionRuleName: containerInsightsDataCollectionRuleName
    adxSkuName: adxSkuName
    adxSkuCapacity: adxSkuCapacity
    userPrincipalNames: userPrincipalNames
    forceScriptRerun: forceScriptRerun
    enableManagedPrometheus: enableManagedPrometheus
    actionGroupName: actionGroupName
    alertEmailReceivers: alertEmailReceivers
    alertOwnerIds: alertOwnerIds
    enableDiagnosticSettings: enableDiagnosticSettings
    enableContainerInsights: enableContainerInsights
    dashboardDefinitions: dashboardDefinitions
  }
  dependsOn: [
    aks
  ]
}

output adxWebExplorerUrl string = observability.outputs.adxWebExplorerUrl
output grafanaEndpoint string = observability.outputs.grafanaEndpoint
output logAnalyticsPortalUrl string = observability.outputs.logAnalyticsPortalUrl
output azureMonitorAlertPortalUrls array = observability.outputs.azureMonitorAlertPortalUrls
