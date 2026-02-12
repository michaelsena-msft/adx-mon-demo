using 'main.bicep'

// Required: UPN emails for ADX Viewer + Grafana Admin access.
// For TME tenant, use alias@tme01.onmicrosoft.com
param userPrincipalNames = [
  'yourname@yourtenant.onmicrosoft.com'
]

// Optional features — uncomment to enable:
// param enableManagedPrometheus = true
// param enableFullPrometheusMetrics = true
// param enableACNS = true
// param enableContainerInsights = true
// param enableDiagnosticSettings = true
