@description('Name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('Principal ID of the Grafana managed identity to grant Monitoring Reader.')
param grafanaPrincipalId string

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

resource law 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource grafanaLawReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(law.id, grafanaPrincipalId, monitoringReaderRoleId)
  scope: law
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: grafanaPrincipalId
    principalType: 'ServicePrincipal'
  }
}
