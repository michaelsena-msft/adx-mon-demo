@description('Name of the existing AKS cluster.')
param aksClusterName string

@description('Azure region for all resources.')
param location string

@description('Name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'law-adx-mon'

@description('Log Analytics workspace retention in days.')
param retentionInDays int = 30

// AKS control-plane log categories recommended by the AKS Baseline Architecture.
// kube-audit-admin is preferred over kube-audit (excludes GET/LIST — significantly cheaper).
// Ref: https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-resource-logs
var logCategories = [
  'kube-audit-admin'
  'kube-controller-manager'
  'cluster-autoscaler'
  'guard'
]

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

resource law 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: retentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

#disable-next-line use-recent-api-versions // 2021-05-01-preview is the latest available for diagnostic settings
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aks-control-plane'
  scope: aks
  properties: {
    workspaceId: law.id
    logs: [for category in logCategories: {
      category: category
      enabled: true
    }]
  }
}

output logAnalyticsWorkspaceId string = law.id
