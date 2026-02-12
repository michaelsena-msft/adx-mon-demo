using 'main.bicep'

// Deployment location and resource group (defaults: eastus2, rg-adx-mon)
// param location = 'westus2'
// param resourceGroupName = 'rg-my-adxmon'

// Required: UPN emails for ADX Viewer + Grafana Admin access.
// For TME tenant, use alias@tme01.onmicrosoft.com
param userPrincipalNames = [
  'yourname@yourtenant.onmicrosoft.com'
]

// All features are enabled by default. Uncomment to disable:
// param enableManagedPrometheus = false
// param enableFullPrometheusMetrics = false
// param enableContainerInsights = false
// param enableDiagnosticSettings = false
