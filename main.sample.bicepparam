using 'main.bicep'

// SAMPLE ONLY: Copy to main.bicepparam and replace placeholder values.
// Do NOT commit real parameter values.

// ---------- Access (recommended) ----------

// User principal names (aliases or UPNs) to grant ADX Viewer + Grafana Admin access.
param userPrincipalNames = [
  ''
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

// AKS resource name (default: aks-adx-mon)
// param aksClusterName = 'aks-adx-mon'
// If subscription quota is constrained, reduce AKS nodes for test runs:
// param nodeCount = 1
// param nodeVmSize = 'Standard_D4s_v3'

// Grafana workspace name must be globally unique across Azure.
// Uncomment and set a unique value if deployment reports NameNotUnique.
// param grafanaName = 'grafana-adx-mon-youralias'

// ADX cluster name must be globally unique in the subscription.
// Uncomment and set a unique value if deployment reports InvalidClusterName.
// param adxClusterName = 'adxmonyouralias123'

// For observability naming/tuning overrides, deploy observability.bicep directly.
