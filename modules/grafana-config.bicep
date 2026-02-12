// Configures Grafana with ADX datasource and optional dashboards

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

@description('Dashboard definitions to provision. Each entry has a title and a JSON model string.')
param dashboardDefinitions array = []

resource grafana 'Microsoft.Dashboard/grafana@2024-10-01' existing = {
  name: grafanaName
}

// Grant deployer identity Grafana Admin to configure datasource
resource grafanaAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, deployerPrincipalId, '22926164-76b3-42b3-bc55-97df8dab3e41')
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
      { name: 'DASHBOARD_DEFINITIONS', value: string(dashboardDefinitions) }
    ]
    scriptContent: '''
      set -e
      az extension add --name amg -y 2>/dev/null || true

      echo "Waiting 60s for role propagation..."
      sleep 60

      EXISTING_UID=$(az grafana data-source show -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --data-source "$ADX_NAME" --query uid -o tsv 2>/dev/null || true)
      if [ -n "$EXISTING_UID" ]; then
        echo "ADX datasource already exists (uid=$EXISTING_UID), updating..."
        az grafana data-source update -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --data-source "$EXISTING_UID" --definition '{
          "name":"'"$ADX_NAME"'",
          "uid":"'"$EXISTING_UID"'",
          "type":"grafana-azure-data-explorer-datasource",
          "access":"proxy",
          "jsonData":{"clusterUrl":"'"$ADX_URL"'"}
        }'
      else
        echo "Creating ADX datasource..."
        az grafana data-source create -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --definition '{
          "name":"'"$ADX_NAME"'",
          "type":"grafana-azure-data-explorer-datasource",
          "access":"proxy",
          "jsonData":{"clusterUrl":"'"$ADX_URL"'"}
        }'
      fi

      # Provision dashboards if any are defined
      if [ "$DASHBOARD_DEFINITIONS" != "[]" ]; then
        echo "$DASHBOARD_DEFINITIONS" | python3 -c "
import json, sys, subprocess
defs = json.load(sys.stdin)
for d in defs:
    title = d['title']
    model = json.dumps(d['definition'])
    uid = d['definition'].get('uid', '')
    if uid:
        print(f'Deleting existing dashboard {uid} (if any)...')
        subprocess.run([
            'az', 'grafana', 'dashboard', 'delete',
            '-n', '$GRAFANA_NAME', '-g', '$GRAFANA_RG',
            '--dashboard', uid
        ], capture_output=True)
    print(f'Creating dashboard: {title}')
    subprocess.run([
        'az', 'grafana', 'dashboard', 'create',
        '-n', '$GRAFANA_NAME', '-g', '$GRAFANA_RG',
        '--title', title,
        '--definition', model
    ], check=True)
"
        echo "Dashboard provisioning complete."
      fi

      echo "Grafana configuration complete."
    '''
  }
}
