@description('Azure region for all resources.')
param location string

@description('Name of the existing Grafana workspace to link to the Azure Monitor Workspace.')
param grafanaName string

@description('Principal ID of the Grafana managed identity to grant Monitoring Reader.')
param grafanaPrincipalId string

@description('Name of the Azure Monitor Workspace.')
param azureMonitorWorkspaceName string

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

resource amw 'Microsoft.Monitor/accounts@2023-04-03' existing = {
  name: azureMonitorWorkspaceName
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
