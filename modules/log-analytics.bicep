@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Azure region for the workspace.')
param location string

resource law 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: workspaceName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

