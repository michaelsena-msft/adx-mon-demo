@description('Azure region for all resources.')
param location string

@description('Name of the existing AKS cluster to enable Prometheus metrics on.')
param aksClusterName string

@description('Name of the Azure Monitor Workspace.')
param azureMonitorWorkspaceName string = 'amw-adx-mon'

@description('Name of the Data Collection Endpoint.')
param dataCollectionEndpointName string = 'dce-adx-mon'

@description('Name of the Data Collection Rule for Prometheus.')
param dataCollectionRuleName string = 'dcr-adx-mon-prometheus'

@description('Principal ID of the Grafana managed identity to grant Monitoring Reader.')
param grafanaPrincipalId string

@description('Name of the existing Grafana workspace to link to the Azure Monitor Workspace.')
param grafanaName string

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

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
  properties: {
    azureMonitorProfile: {
      metrics: {
        enabled: true
      }
    }
  }
}

resource grafanaMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(amw.id, grafanaPrincipalId, monitoringReaderRoleId)
  scope: amw
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: grafanaPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource grafanaAmwLink 'Microsoft.Dashboard/grafana@2024-10-01' = {
  name: grafanaName
  location: location
  properties: {
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: amw.id
        }
      ]
    }
  }
}

@description('Resource ID of the Azure Monitor Workspace.')
output azureMonitorWorkspaceId string = amw.id
