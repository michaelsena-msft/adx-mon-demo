@description('Azure region for alert resources.')
param location string

@description('Resource ID of the AKS cluster.')
param aksClusterId string

@description('Resource ID of the Azure Monitor Workspace (AMW).')
param azureMonitorWorkspaceId string

@description('Resource ID of the Action Group that should receive alert notifications.')
param actionGroupResourceId string

#disable-next-line no-deployments-resources
resource recommendedMetricAlertsTemplate 'Microsoft.Resources/deployments@2024-03-01' = {
  name: 'recommended-metric-alerts-template'
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: 'https://raw.githubusercontent.com/Azure/prometheus-collector/main/GeneratedMonitoringArtifacts/Default/recommendedMetricAlerts.json'
      contentVersion: '1.0.0.0'
    }
    parameters: {
      clusterResourceId: {
        value: aksClusterId
      }
      actionGroupResourceId: {
        value: actionGroupResourceId
      }
      azureMonitorWorkspaceResourceId: {
        value: azureMonitorWorkspaceId
      }
      location: {
        value: location
      }
    }
  }
}
