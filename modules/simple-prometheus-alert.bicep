@description('Azure region for alert resources.')
param location string

@description('Resource ID of the AKS cluster.')
param aksClusterId string

@description('Name of the AKS cluster.')
param aksClusterName string

@description('Resource ID of the Azure Monitor Workspace (AMW).')
param azureMonitorWorkspaceId string

@description('Resource ID of the Action Group that should receive alert notifications.')
param actionGroupResourceId string

@description('Alert owner/contact identifiers used as metadata labels and tags.')
param alertOwnerIds string[]

var ownerLabel = join(alertOwnerIds, ',')

resource simpleCustomAlertRuleGroup 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: 'DemoCustomAlertsRuleGroup-${aksClusterName}'
  location: location
  tags: {
    owners: ownerLabel
    source: 'custom-demo'
  }
  properties: {
    description: 'Simple custom Prometheus alert rule group for deployment examples.'
    scopes: [
      azureMonitorWorkspaceId
      aksClusterId
    ]
    clusterName: aksClusterName
    enabled: true
    interval: 'PT1M'
    rules: [
      {
        alert: 'DemoKubePodFailedState'
        expression: 'sum by (cluster, namespace) (kube_pod_status_phase{phase="Failed",job="kube-state-metrics"}) > 0'
        for: 'PT5M'
        annotations: {
          description: 'Demo custom alert: one or more pods are in Failed state.'
        }
        labels: {
          severity: 'warning'
          owners: ownerLabel
          source: 'custom-demo'
        }
        enabled: true
        severity: 3
        resolveConfiguration: {
          autoResolved: true
          timeToResolve: 'PT10M'
        }
        actions: [
          {
            actionGroupId: actionGroupResourceId
          }
        ]
      }
    ]
  }
}

output customAlertRuleGroupName string = simpleCustomAlertRuleGroup.name
