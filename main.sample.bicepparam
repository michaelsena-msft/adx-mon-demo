using 'main.bicep'

// SAMPLE ONLY: Copy to main.bicepparam and replace placeholder values.
// Do NOT commit real parameter values.

// ---------- Access (recommended) ----------

// UPN emails to grant ADX Viewer + Grafana Admin access.
// For TME tenant, use alias@tme01.onmicrosoft.com
param userPrincipalNames = [
  'yourname@yourtenant.onmicrosoft.com'
]

// ---------- Alerts (required) ----------

// Email receivers for Azure Monitor alert notifications (Action Group is created by this deployment).
param alertEmailReceivers = [
  {
    name: 'primary'
    emailAddress: 'yourname@yourtenant.onmicrosoft.com'
  }
]

// Alert owner/contact identifiers used as alert metadata (for example: aliases).
param alertOwnerIds = [
  'youralias'
]

// ---------- Common optional overrides ----------

// Deployment location and resource group (defaults: eastus2, rg-adx-mon)
// param location = 'westus2'
// param resourceGroupName = 'rg-my-adxmon'

// Resource names (override if you need multiple deployments per subscription/resource group)
// param aksClusterName = 'aks-adx-mon'
// param adxClusterName = 'adxmon<unique>' // globally unique, lowercase alphanumeric, max 22 chars
// param grafanaName = 'grafana-adx-mon'
// param adxMonIdentityName = 'id-adx-mon'
// param deployerIdentityName = 'id-adx-mon-deployer'
// param logAnalyticsWorkspaceName = 'law-adx-mon'
// param azureMonitorWorkspaceName = 'amw-adx-mon'
// param managedPrometheusDataCollectionEndpointName = 'dce-adx-mon'
// param managedPrometheusDataCollectionRuleName = 'dcr-adx-mon-prometheus'
// param containerInsightsDataCollectionEndpointName = 'dce-adx-mon-ci'
// param containerInsightsDataCollectionRuleName = 'dcr-adx-mon-ci'
// param actionGroupName = 'ag-adx-mon'

// AKS sizing (defaults: Standard_D4s_v3, 2)
// param nodeVmSize = 'Standard_D4s_v3'
// param nodeCount = 2

// ADX sizing (defaults: Standard_E2ads_v5, 2)
// param adxSkuName = 'Standard_E2ads_v5'
// param adxSkuCapacity = 2

// Enable/disable optional integrations (defaults: true)
// param enableManagedPrometheus = false
// param enableContainerInsights = false
// param enableDiagnosticSettings = false

// Force deployment scripts to re-run (default: '')
// param forceScriptRerun = '20260214T235959Z'

// Additional Grafana dashboards to provision (default: [])
// param dashboardDefinitions = [
//   {
//     title: 'My Dashboard'
//     definition: { /* Grafana JSON model */ }
//   }
// ]
