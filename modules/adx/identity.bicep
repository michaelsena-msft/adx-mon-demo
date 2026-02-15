@description('Name of the adx-mon workload identity.')
param adxMonIdentityName string

@description('Name of the AKS script deployer managed identity.')
param aksScriptDeployerIdentityName string

@description('Azure region for all resources.')
param location string

@description('OIDC issuer URL of the AKS cluster for federated credentials.')
param aksOidcIssuerUrl string

@description('Name of the AKS cluster for scoped role assignments.')
param aksClusterName string

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

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

// User-Assigned Managed Identity for AKS deployment scripts
resource aksScriptDeployerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: aksScriptDeployerIdentityName
  location: location
}

// Give the deployer identity "Azure Kubernetes Service Cluster Admin Role" on the AKS cluster
resource aksClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, aksScriptDeployerIdentity.id, '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
    principalId: aksScriptDeployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Give the deployer identity "Azure Kubernetes Service RBAC Cluster Admin" on the AKS cluster
// Required for clusters with Azure RBAC enabled (disableLocalAccounts: true)
resource aksRbacClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, aksScriptDeployerIdentity.id, 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
    principalId: aksScriptDeployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Give the deployer identity "Contributor" on the resource group
resource rgContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, aksScriptDeployerIdentity.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: aksScriptDeployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output adxMonIdentityClientId string = adxMonIdentity.properties.clientId
output aksScriptDeployerIdentityId string = aksScriptDeployerIdentity.id
output aksScriptDeployerPrincipalId string = aksScriptDeployerIdentity.properties.principalId
