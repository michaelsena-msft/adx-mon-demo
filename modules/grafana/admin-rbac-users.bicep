@description('Name of the Grafana workspace.')
param grafanaName string

@description('User principal IDs to grant Grafana Admin access.')
param adminPrincipalIds string[] = []

resource grafana 'Microsoft.Dashboard/grafana@2024-10-01' existing = {
  name: grafanaName
}

resource grafanaAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in adminPrincipalIds: {
  name: guid(grafana.id, principalId, '22926164-76b3-42b3-bc55-97df8dab3e41')
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')
    principalId: principalId
    principalType: 'User'
  }
}]
