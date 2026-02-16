// Configures Grafana with ADX datasource and optional dashboards

type DashboardDefinition = {
  title: string
  definition: object
}

@description('Azure region for the deployment script resource.')
param location string

@description('Name of the Grafana workspace.')
param grafanaName string

@description('ADX cluster URI.')
param adxUri string

@description('Name of the ADX cluster.')
param adxClusterName string

@description('Resource ID of the Grafana config deployer managed identity.')
param grafanaConfigDeployerIdentityId string

@description('Principal ID of the Grafana config deployer managed identity.')
param grafanaConfigDeployerPrincipalId string

@description('Set to any unique value to force the deployment script to re-execute. Leave empty for normal behavior.')
param forceScriptRerun string = ''

@description('Dashboard definitions to provision. Each entry has a title and a JSON model object.')
param dashboardDefinitions DashboardDefinition[] = []

@description('Resource ID of the Log Analytics workspace used for dashboard log panels.')
param logAnalyticsWorkspaceResourceId string = ''

resource grafana 'Microsoft.Dashboard/grafana@2024-10-01' existing = {
  name: grafanaName
}

var readerRoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// Grant deployer identity Grafana Admin to configure datasource
resource grafanaAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, grafanaConfigDeployerPrincipalId, '22926164-76b3-42b3-bc55-97df8dab3e41')
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')
    principalId: grafanaConfigDeployerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Grant deployer identity ARM read permission on Grafana workspace resource
resource grafanaReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, grafanaConfigDeployerPrincipalId, readerRoleDefinitionId)
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleDefinitionId)
    principalId: grafanaConfigDeployerPrincipalId
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
      '${grafanaConfigDeployerIdentityId}': {}
    }
  }
  dependsOn: [
    grafanaAdminRole
    grafanaReaderRole
  ]
  properties: {
    azCliVersion: '2.63.0'
    retentionInterval: 'PT1H'
    timeout: 'PT15M'
    forceUpdateTag: forceScriptRerun != '' ? forceScriptRerun : 'stable'
    environmentVariables: [
      { name: 'GRAFANA_NAME', value: grafanaName }
      { name: 'GRAFANA_RG', value: resourceGroup().name }
      { name: 'ADX_URL', value: adxUri }
      { name: 'ADX_NAME', value: adxClusterName }
      { name: 'DASHBOARD_DEFINITIONS', value: string(dashboardDefinitions) }
      { name: 'LAW_RESOURCE_ID', value: logAnalyticsWorkspaceResourceId }
    ]
    scriptContent: '''
      set -e
      az extension add --name amg -y 2>/dev/null || true

      # Retry-based RBAC propagation check (replaces fixed sleep 60)
      MAX_RETRIES=12
      RETRY_INTERVAL=10
      EXISTING_UID=""
      for i in $(seq 1 $MAX_RETRIES); do
        EXISTING_UID=$(az grafana data-source show -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --data-source "$ADX_NAME" --query uid -o tsv 2>/dev/null) && break
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 3 ]; then
          break  # datasource not found but API is accessible — proceed to create
        fi
        echo "Waiting for Grafana RBAC propagation... (attempt $i/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
      done

      if [ -n "$EXISTING_UID" ]; then
        echo "ADX datasource already exists (uid=$EXISTING_UID), updating..."
        az grafana data-source update -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --data-source "$EXISTING_UID" --definition '{
          "name":"'"$ADX_NAME"'",
          "uid":"adx-adx-mon",
          "type":"grafana-azure-data-explorer-datasource",
          "access":"proxy",
          "jsonData":{"clusterUrl":"'"$ADX_URL"'"}
        }'
      else
        echo "Creating ADX datasource..."
        az grafana data-source create -n "$GRAFANA_NAME" -g "$GRAFANA_RG" --definition '{
          "name":"'"$ADX_NAME"'",
          "uid":"adx-adx-mon",
          "type":"grafana-azure-data-explorer-datasource",
          "access":"proxy",
          "jsonData":{"clusterUrl":"'"$ADX_URL"'"}
        }'
      fi

      # Provision dashboards if any are defined
      if [ "$DASHBOARD_DEFINITIONS" != "[]" ]; then
        echo "$DASHBOARD_DEFINITIONS" | python3 -c "
import json, os, re, subprocess, sys
defs = json.load(sys.stdin)
law_resource_id = os.environ.get('LAW_RESOURCE_ID', '')
hardcoded_law_id_pattern = re.compile(r'/subscriptions/[^"]+/resourceGroups/[^"]+/providers/Microsoft\\.OperationalInsights/workspaces/[^"]+', re.IGNORECASE)
for d in defs:
    title = d['title']
    definition = d['definition']
    model = json.dumps(definition)
    if hardcoded_law_id_pattern.search(model):
        raise SystemExit(f'Dashboard {title!r} contains a hard-coded Log Analytics workspace resource ID. Use __LAW_RESOURCE_ID__.')
    if '__LAW_RESOURCE_ID__' in model:
        if not law_resource_id:
            raise SystemExit(f'Dashboard {title!r} uses __LAW_RESOURCE_ID__ but LAW_RESOURCE_ID is empty.')
        model = model.replace('__LAW_RESOURCE_ID__', law_resource_id)
    uid = definition.get('uid', '')
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
