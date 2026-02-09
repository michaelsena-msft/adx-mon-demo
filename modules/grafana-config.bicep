// Configures Grafana with ADX datasource (no dashboard deployment)

@description('Azure region for the deployment script resource.')
param location string

@description('Name of the Grafana workspace.')
param grafanaName string

@description('ADX cluster URI.')
param adxUri string

@description('Name of the ADX cluster.')
param adxClusterName string

@description('Resource ID of the deployer managed identity.')
param deployerIdentityId string

@description('Principal ID of the deployer managed identity.')
param deployerPrincipalId string

@description('Force re-run of the deployment script.')
param forceUpdateTag string = utcNow()

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: grafanaName
}

// Grant deployer identity Grafana Admin to configure datasource
resource grafanaAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, deployerPrincipalId, 'GrafanaAdmin')
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')
    principalId: deployerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource configScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'configure-grafana-datasource'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deployerIdentityId}': {}
    }
  }
  dependsOn: [
    grafanaAdminRole
  ]
  properties: {
    azCliVersion: '2.63.0'
    retentionInterval: 'PT1H'
    timeout: 'PT15M'
    forceUpdateTag: forceUpdateTag
    environmentVariables: [
      { name: 'GRAFANA_NAME', value: grafanaName }
      { name: 'GRAFANA_RG', value: resourceGroup().name }
      { name: 'ADX_URL', value: adxUri }
      { name: 'ADX_NAME', value: adxClusterName }
    ]
    scriptContent: '''
      set -e
      az extension add --name amg -y 2>/dev/null || true

      echo "Waiting 60s for role propagation..."
      sleep 60

      if ! az grafana data-source show -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --data-source "$ADX_NAME" 2>/dev/null; then
        echo "Creating ADX datasource..."
        az grafana data-source create -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --definition '{
          "name":"'"$ADX_NAME"'",
          "type":"grafana-azure-data-explorer-datasource",
          "access":"proxy",
          "jsonData":{"clusterUrl":"'"$ADX_URL"'"}
        }'
      else
        echo "ADX datasource already exists."
      fi
      echo "Grafana datasource configuration complete."
    '''
  }
}
