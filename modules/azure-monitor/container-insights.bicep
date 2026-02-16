@description('Name of the existing AKS cluster.')
param aksClusterName string

@description('Identity type of the existing AKS cluster.')
param aksIdentityType string = 'SystemAssigned'

@description('DNS prefix of the existing AKS cluster.')
param aksDnsPrefix string

@description('Agent pool profiles of the existing AKS cluster.')
param aksAgentPoolProfiles array

@description('Azure region for all resources.')
param location string

@description('Resource ID of the Log Analytics workspace for Container Insights data.')
param logAnalyticsWorkspaceId string

@description('Existing Data Collection Endpoint ID (e.g. from Managed Prometheus). If empty, a new DCE is created.')
param existingDataCollectionEndpointId string = ''

@description('Name of the Data Collection Endpoint for Container Insights (used only when no existing DCE is provided).')
param dataCollectionEndpointName string

@description('Name of the Data Collection Rule for Container Insights.')
param dataCollectionRuleName string

var createDce = empty(existingDataCollectionEndpointId)
var effectiveDceId = createDce ? dce.id : existingDataCollectionEndpointId

// Collect ContainerLogV2, KubePodInventory, KubeEvents.
// Exclude kube-system to reduce noise; coredns logs available via adx-mon annotations.
var ciStreams = [
  'Microsoft-ContainerLogV2'
  'Microsoft-KubePodInventory'
  'Microsoft-KubeEvents'
]

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// Only create a DCE when Managed Prometheus isn't providing one
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' = if (createDce) {
  name: dataCollectionEndpointName
  location: location
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dataCollectionRuleName
  location: location
  kind: 'Linux'
  properties: {
    dataCollectionEndpointId: effectiveDceId
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: ciStreams
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              namespaceFilteringMode: 'Exclude'
              namespaces: [ 'kube-system' ]
              enableContainerLogV2: true
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'ciWorkspace'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ciStreams
        destinations: [ 'ciWorkspace' ]
      }
    ]
  }
}

// Only create DCE association when we own the DCE (otherwise MP already set configurationAccessEndpoint)
resource dceAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = if (createDce) {
  name: 'configurationAccessEndpoint'
  scope: aksCluster
  properties: {
    dataCollectionEndpointId: effectiveDceId
    description: 'DCE association for Container Insights'
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dcr.id
    description: 'DCR association for Container Insights'
  }
}

// Enable the monitoring addon on AKS (deploys ama-logs DaemonSet)
resource aksMonitoringUpdate 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksClusterName
  location: location
  identity: {
    type: aksIdentityType
  }
  properties: {
    dnsPrefix: aksDnsPrefix
    agentPoolProfiles: aksAgentPoolProfiles
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
  }
}

output dataCollectionEndpointId string = effectiveDceId
