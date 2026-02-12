@description('Name of the Grafana workspace.')
param grafanaName string

@description('Azure region for the Grafana workspace.')
param location string

@description('SKU name for the Grafana workspace.')
param skuName string = 'Standard'


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

output grafanaName string = grafana.name
output grafanaEndpoint string = grafana.properties.endpoint
output grafanaPrincipalId string = grafana.identity.principalId
