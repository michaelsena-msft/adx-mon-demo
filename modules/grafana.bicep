@description('Name of the Grafana workspace.')
param grafanaName string

@description('Azure region for the Grafana workspace.')
param location string

@description('SKU name for the Grafana workspace.')
param skuName string = 'Standard'

@description('Principal IDs to grant Grafana Admin role')
param adminPrincipalIds string[] = []

@description('Principal type for admin principals (User or Group)')
param adminPrincipalType string = 'User'

resource grafana 'Microsoft.Dashboard/grafana@2024-10-01' = {
  name: grafanaName
  location: location
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    zoneRedundancy: 'Disabled'
    publicNetworkAccess: 'Enabled'
    grafanaMajorVersion: '11'
  }
}

// Grafana Admin role for specified principals
resource grafanaAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in adminPrincipalIds: {
  name: guid(grafana.id, principalId, '22926164-76b3-42b3-bc55-97df8dab3e41')
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')
    principalId: principalId
    principalType: adminPrincipalType
  }
}]

output grafanaName string = grafana.name
output grafanaEndpoint string = grafana.properties.endpoint
output grafanaPrincipalId string = grafana.identity.principalId
