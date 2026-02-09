using 'main.bicep'

param resourceGroupName = 'rg-adx-mon'
param location = 'eastus2'
param aksClusterName = 'aks-adx-mon'
param grafanaName = 'grafana-adx-mon'
param nodeVmSize = 'Standard_D4s_v3'
param nodeCount = 2
param adxSkuName = 'Standard_E2ads_v5'
param adxSkuCapacity = 2

// Add principal object IDs here to grant ADX Viewer + Grafana Admin access
param userPrincipalIds = []
// param userTenantId = '<your-tenant-id>'
