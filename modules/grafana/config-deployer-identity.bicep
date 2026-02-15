@description('Name of the Grafana config deployer managed identity.')
param grafanaConfigDeployerIdentityName string

@description('Azure region for all resources.')
param location string

resource grafanaConfigDeployerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: grafanaConfigDeployerIdentityName
  location: location
}

output grafanaConfigDeployerIdentityId string = grafanaConfigDeployerIdentity.id
output grafanaConfigDeployerPrincipalId string = grafanaConfigDeployerIdentity.properties.principalId
