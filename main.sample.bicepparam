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
param userPrincipalIds = [
  'aaaa1111-bb22-cc33-dd44-eeeeee000001'
  'aaaa1111-bb22-cc33-dd44-eeeeee000002'
]
// param userTenantId = 'bbbb2222-cccc-dddd-eeee-ffffffffffff'

// Enable Managed Prometheus for AKS metrics collection
// param enableManagedPrometheus = true

// Enable full Prometheus metrics profile and pod-annotation scraping
// (requires enableManagedPrometheus = true)
// param enableFullPrometheusMetrics = false

// Enable AKS control-plane diagnostic settings (logs to Log Analytics)
// param enableDiagnosticSettings = false

// Enable Container Insights for AKS log collection (ContainerLogV2, KubePodInventory, KubeEvents)
// param enableContainerInsights = false
