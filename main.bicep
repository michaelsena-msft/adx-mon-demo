targetScope = 'subscription'

// ---------- Parameters ----------

@description('Name of the resource group.')
param resourceGroupName string = 'rg-adx-mon'

@description('Azure region for all resources.')
param location string = 'eastus2'

@description('Name of the AKS managed cluster.')
param aksClusterName string = 'aks-adx-mon'

@description('Globally unique name for the ADX cluster (lowercase alphanumeric only).')
@maxLength(22)
param adxClusterName string = 'adxmon${uniqueString(subscription().id)}'

@description('Name of the Grafana workspace.')
param grafanaName string = 'grafana-adx-mon'

@description('VM size for the AKS system node pool.')
param nodeVmSize string = 'Standard_D4s_v3'

@description('Number of nodes in the AKS system node pool.')
param nodeCount int = 2

@description('SKU name for the ADX cluster.')
param adxSkuName string = 'Standard_E2ads_v5'

@description('SKU capacity (instance count) for the ADX cluster.')
param adxSkuCapacity int = 2

@description('User principal (object) IDs to grant ADX Viewer and Grafana Admin access.')
param userPrincipalIds string[] = []

@description('Tenant ID for user principals (defaults to current tenant).')
param userTenantId string = tenant().tenantId

@description('Force update tag for deployment scripts and Kusto scripts.')
param deployTimestamp string = utcNow()

@description('Enable Managed Prometheus for AKS metrics collection.')
param enableManagedPrometheus bool = false

// ---------- Resource Group ----------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

// ---------- AKS ----------

module aks 'modules/aks.bicep' = {
  scope: rg
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    nodeVmSize: nodeVmSize
    nodeCount: nodeCount
  }
}

// ---------- ADX (parallel with AKS) ----------

module adx 'modules/adx.bicep' = {
  scope: rg
  name: 'adx-deployment'
  params: {
    clusterName: adxClusterName
    location: location
    skuName: adxSkuName
    skuCapacity: adxSkuCapacity
    forceUpdateTag: deployTimestamp
  }
}

// ---------- Identity (needs AKS OIDC URL) ----------

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity-deployment'
  params: {
    location: location
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    aksClusterName: aks.outputs.aksName
  }
}

// ---------- Grafana (parallel, with user admin access) ----------

module grafana 'modules/grafana.bicep' = {
  scope: rg
  name: 'grafana-deployment'
  params: {
    grafanaName: grafanaName
    location: location
    adminPrincipalIds: userPrincipalIds
  }
}

// ---------- Managed Prometheus (optional, needs AKS and Grafana) ----------

module managedPrometheus 'modules/managed-prometheus.bicep' = if (enableManagedPrometheus) {
  scope: rg
  name: 'managed-prometheus-deployment'
  params: {
    location: location
    aksClusterName: aks.outputs.aksName
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    grafanaName: grafana.outputs.grafanaName
  }
}

// ---------- Role Assignments (needs ADX, identity, grafana) ----------

module roleAssignments 'modules/role-assignments.bicep' = {
  scope: rg
  name: 'role-assignments-deployment'
  params: {
    adxClusterName: adx.outputs.adxName
    adxMonAppId: identity.outputs.adxMonIdentityClientId
    grafanaPrincipalId: grafana.outputs.grafanaPrincipalId
    viewerPrincipalIds: userPrincipalIds
    viewerTenantId: userTenantId
  }
}

// ---------- K8s Workloads (needs AKS, ADX, identity, roleAssignments) ----------

module k8sWorkloads 'modules/k8s-workloads.bicep' = {
  scope: rg
  name: 'k8s-workloads-deployment'
  dependsOn: [
    roleAssignments
  ]
  params: {
    location: location
    aksClusterName: aks.outputs.aksName
    adxUri: adx.outputs.adxUri
    adxMonClientId: identity.outputs.adxMonIdentityClientId
    clusterName: aksClusterName
    region: location
    deployerIdentityId: identity.outputs.deployerIdentityId
    forceUpdateTag: deployTimestamp
  }
}

// ---------- Grafana Config — datasource only, no dashboards ----------

module grafanaConfig 'modules/grafana-config.bicep' = {
  scope: rg
  name: 'grafana-config-deployment'
  dependsOn: [
    k8sWorkloads
  ]
  params: {
    location: location
    grafanaName: grafana.outputs.grafanaName
    adxUri: adx.outputs.adxUri
    adxClusterName: adx.outputs.adxName
    deployerIdentityId: identity.outputs.deployerIdentityId
    deployerPrincipalId: identity.outputs.deployerPrincipalId
    forceUpdateTag: deployTimestamp
  }
}

// ---------- Outputs ----------

output aksClusterName string = aks.outputs.aksName
output adxClusterUri string = adx.outputs.adxUri
output adxWebExplorerUrl string = 'https://dataexplorer.azure.com/clusters/${replace(adx.outputs.adxUri, 'https://', '')}/databases/Metrics'
output grafanaEndpoint string = grafana.outputs.grafanaEndpoint
output resourceGroupName string = rg.name
output azureMonitorWorkspaceId string = enableManagedPrometheus ? managedPrometheus.outputs.azureMonitorWorkspaceId : ''
