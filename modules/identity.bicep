@description('Name of the adx-mon workload identity.')
param adxMonIdentityName string = 'id-adx-mon'

@description('Name of the deployer managed identity for deployment scripts.')
param deployerIdentityName string = 'id-adx-mon-deployer'

@description('Azure region for all resources.')
param location string

@description('OIDC issuer URL of the AKS cluster for federated credentials.')
param aksOidcIssuerUrl string

@description('Name of the AKS cluster for scoped role assignments.')
param aksClusterName string

// User-Assigned Managed Identity for adx-mon workloads
resource adxMonIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: adxMonIdentityName
  location: location
}

// Federated identity credential for ingestor service account
resource federatedIngestor 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  name: 'federated-ingestor'
  parent: adxMonIdentity
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:adx-mon:ingestor'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// Federated identity credential for collector service account (serial to avoid concurrent write error)
resource federatedCollector 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  name: 'federated-collector'
  parent: adxMonIdentity
  dependsOn: [
    federatedIngestor
  ]
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:adx-mon:collector'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// User-Assigned Managed Identity for deployment scripts
resource deployerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: deployerIdentityName
  location: location
}

// Give the deployer identity "Azure Kubernetes Service Cluster Admin Role" on the AKS cluster
resource aksClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, deployerIdentity.id, '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
    principalId: deployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference the existing AKS cluster for scoped role assignment
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// Give the deployer identity "Contributor" on the resource group
resource rgContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployerIdentity.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: deployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output adxMonIdentityClientId string = adxMonIdentity.properties.clientId
output deployerIdentityId string = deployerIdentity.id
output deployerPrincipalId string = deployerIdentity.properties.principalId
