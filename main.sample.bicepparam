using 'main.bicep'

// Deployment location and resource group (defaults: eastus2, rg-adx-mon)
// param location = 'westus2'
// param resourceGroupName = 'rg-my-adxmon'

// Required: UPN emails for ADX Viewer + Grafana Admin access.
// For TME tenant, use alias@tme01.onmicrosoft.com
param userPrincipalNames = [
  'yourname@yourtenant.onmicrosoft.com'
]

// Required: Email receivers for Azure Monitor alert notifications (Action Group is created by this deployment).
param alertEmailReceivers = [
  {
    name: 'primary'
    emailAddress: 'yourname@yourtenant.onmicrosoft.com'
  }
]

// Optional: override Action Group name (default: ag-adx-mon)
// param actionGroupName = 'ag-my-adxmon'

// Required: Alert owner/contact identifiers (aliases or IDs) used in alert metadata.
param alertOwnerIds = [
  'youralias'
]

// All features are enabled by default. Uncomment to disable:
// param enableManagedPrometheus = false
// param enableRecommendedMetricAlerts = false
// param enableFullPrometheusMetrics = false
// param enableContainerInsights = false
// param enableDiagnosticSettings = false
