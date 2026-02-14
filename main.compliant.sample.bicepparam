using 'main.bicep'

// SAMPLE ONLY: Deploy into an existing compliant AKS cluster (BYO AKS).
// Copy to main.bicepparam and replace placeholder values.
// Do NOT commit real parameter values.

// Existing AKS cluster (must already exist in the same resource group this deployment uses).
param resourceGroupName = 'rg-your-existing-aks'
param aksClusterName = 'aks-your-existing-cluster'
param createAks = false

// Required when createAks = false.
// Fetch it with:
// az aks show -g <resourceGroupName> -n <aksClusterName> --query oidcIssuerProfile.issuerUrl -o tsv
param existingAksOidcIssuerUrl = 'https://<region>.oic.prod-aks.azure.com/<tenant>/<cluster>/'

// ---------- Access (recommended) ----------

// UPN emails to grant ADX Viewer + Grafana Admin access.
// For TME tenant, use alias@tme01.onmicrosoft.com
param userPrincipalNames = [
  'yourname@yourtenant.onmicrosoft.com'
]

// ---------- Alerts (required) ----------

param alertEmailReceivers = [
  {
    name: 'primary'
    emailAddress: 'yourname@yourtenant.onmicrosoft.com'
  }
]

param alertOwnerIds = [
  'youralias'
]

// ---------- Optional feature toggles ----------

// param enableManagedPrometheus = false
// param enableContainerInsights = false
// param enableDiagnosticSettings = false

