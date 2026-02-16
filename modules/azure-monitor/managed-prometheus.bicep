@description('Azure region for all resources.')
param location string

@description('Name of the existing AKS cluster to enable Prometheus metrics on.')
param aksClusterName string

@description('Identity type of the existing AKS cluster.')
param aksIdentityType string = 'SystemAssigned'

@description('DNS prefix of the existing AKS cluster.')
param aksDnsPrefix string

@description('Agent pool profiles of the existing AKS cluster.')
param aksAgentPoolProfiles array

@description('Name of the Azure Monitor Workspace.')
param azureMonitorWorkspaceName string

@description('Name of the Data Collection Endpoint.')
param dataCollectionEndpointName string

@description('Name of the Data Collection Rule for Prometheus.')
param dataCollectionRuleName string

resource amw 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: azureMonitorWorkspaceName
  location: location
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' = {
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
    dataCollectionEndpointId: dce.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [
            'Microsoft-PrometheusMetrics'
          ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'MonitoringAccount'
          accountResourceId: amw.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccount'
        ]
      }
    ]
  }
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

resource dcra 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'configurationAccessEndpoint'
  scope: aksCluster
  properties: {
    dataCollectionEndpointId: dce.id
    description: 'DCE association for AKS Prometheus metrics'
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'ContainerInsightsMetricsExtension'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: dcr.id
    description: 'DCR association for AKS Prometheus metrics'
  }
}

resource aksMetricsUpdate 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksClusterName
  location: location
  identity: {
    type: aksIdentityType
  }
  properties: {
    dnsPrefix: aksDnsPrefix
    agentPoolProfiles: aksAgentPoolProfiles
    azureMonitorProfile: {
      metrics: {
        enabled: true
      }
    }
  }
}

output azureMonitorWorkspaceId string = amw.id
output dataCollectionEndpointId string = dce.id
