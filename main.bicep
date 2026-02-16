targetScope = 'subscription'

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

@description('Name of the Managed Grafana workspace.')
param grafanaName string = 'grafana-adx-mon'

@description('Globally unique name for the ADX cluster.')
@maxLength(22)
param adxClusterName string = 'adxmon${uniqueString(subscription().id)}'

@description('Email receivers for the Action Group used by alert rules.')
param alertEmailReceivers AlertEmailReceiver[]

@description('Alert owner/contact identifiers used as alert metadata (for example: aliases).')
param alertOwnerIds string[]

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
    alertEmailReceivers: alertEmailReceivers
    alertOwnerIds: alertOwnerIds
  }
  dependsOn: [
    aks
  ]
}

output adxWebExplorerUrl string = observability.outputs.adxWebExplorerUrl
output adxAlertDemoUrl string = observability.outputs.adxAlertDemoUrl
output grafanaEndpoint string = observability.outputs.grafanaEndpoint
output logAnalyticsPortalUrl string = observability.outputs.logAnalyticsPortalUrl
output azureMonitorAlertPortalUrls array = observability.outputs.azureMonitorAlertPortalUrls
