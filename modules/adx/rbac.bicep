@description('Name of the ADX cluster.')
param adxClusterName string

@description('Client ID of the adx-mon managed identity.')
param adxMonAppId string

@description('Principal ID of the Grafana managed identity.')
param grafanaPrincipalId string

@description('User principal IDs to grant ADX Viewer access.')
param viewerPrincipalIds string[] = []

resource adx 'Microsoft.Kusto/clusters@2024-04-13' existing = {
  name: adxClusterName
}

resource metricsDb 'Microsoft.Kusto/clusters/databases@2024-04-13' existing = {
  parent: adx
  name: 'Metrics'
}

resource logsDb 'Microsoft.Kusto/clusters/databases@2024-04-13' existing = {
  parent: adx
  name: 'Logs'
}

resource adxMonMetricsAdmin 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = {
  parent: metricsDb
  name: guid(metricsDb.id, adxMonAppId, 'Admin')
  properties: {
    principalId: adxMonAppId
    principalType: 'App'
    role: 'Admin'
    tenantId: tenant().tenantId
  }
}

resource adxMonLogsAdmin 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = {
  parent: logsDb
  name: guid(logsDb.id, adxMonAppId, 'Admin')
  properties: {
    principalId: adxMonAppId
    principalType: 'App'
    role: 'Admin'
    tenantId: tenant().tenantId
  }
}

resource grafanaMetricsViewer 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = {
  parent: metricsDb
  name: guid(metricsDb.id, grafanaPrincipalId, 'Viewer')
  properties: {
    principalId: grafanaPrincipalId
    principalType: 'App'
    role: 'Viewer'
    tenantId: tenant().tenantId
  }
}

resource grafanaLogsViewer 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = {
  parent: logsDb
  name: guid(logsDb.id, grafanaPrincipalId, 'Viewer')
  properties: {
    principalId: grafanaPrincipalId
    principalType: 'App'
    role: 'Viewer'
    tenantId: tenant().tenantId
  }
}

resource userMetricsViewer 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = [for principalId in viewerPrincipalIds: {
  parent: metricsDb
  name: guid(metricsDb.id, principalId, 'Viewer')
  properties: {
    principalId: principalId
    principalType: 'User'
    role: 'Viewer'
    tenantId: tenant().tenantId
  }
}]

resource userLogsViewer 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = [for principalId in viewerPrincipalIds: {
  parent: logsDb
  name: guid(logsDb.id, principalId, 'Viewer')
  properties: {
    principalId: principalId
    principalType: 'User'
    role: 'Viewer'
    tenantId: tenant().tenantId
  }
}]
