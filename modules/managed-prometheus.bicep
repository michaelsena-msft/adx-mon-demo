@description('Azure region for all resources.')
param location string

@description('Name of the existing AKS cluster to enable Prometheus metrics on.')
param aksClusterName string

@description('Name of the Azure Monitor Workspace.')
param azureMonitorWorkspaceName string

@description('Name of the Data Collection Endpoint.')
param dataCollectionEndpointName string

@description('Name of the Data Collection Rule for Prometheus.')
param dataCollectionRuleName string

@description('Existing Data Collection Endpoint ID (e.g. from Container Insights). If empty, a new DCE is created.')
param existingDataCollectionEndpointId string = ''

@description('Principal ID of the Grafana managed identity to grant Monitoring Reader.')
param grafanaPrincipalId string

@description('Name of the existing Grafana workspace to link to the Azure Monitor Workspace.')
param grafanaName string

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var createDce = empty(existingDataCollectionEndpointId)
var effectiveDceId = createDce ? dce.id : existingDataCollectionEndpointId

resource amw 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: azureMonitorWorkspaceName
  location: location
}

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

// Only create DCE association when we own the DCE (otherwise CI already set configurationAccessEndpoint)
resource dcra 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = if (createDce) {
  name: 'configurationAccessEndpoint'
  scope: aksCluster
  properties: {
    dataCollectionEndpointId: effectiveDceId
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
  sku: {
    name: 'Standard'
  }
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
