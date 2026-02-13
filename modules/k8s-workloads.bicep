// Deployment script to apply K8s manifests (CRDs + workloads) to AKS
targetScope = 'resourceGroup'

@description('Azure region for the deployment script resource')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('ADX cluster URI')
param adxUri string

@description('Client ID of the adx-mon managed identity')
param adxMonClientId string

@description('Logical name for the AKS cluster (used in telemetry labels)')
param clusterName string

@description('Azure region value for collector config')
param region string

@description('Resource ID of the deployer managed identity for the deployment script')
param deployerIdentityId string

@description('Set to any unique value to force the deployment script to re-execute. Leave empty for normal behavior.')
param forceScriptRerun string = ''

var crdsYaml = loadTextContent('../k8s/crds.yaml')
var ingestorYaml = loadTextContent('../k8s/ingestor.yaml')
var collectorYaml = loadTextContent('../k8s/collector.yaml')
var ksmYaml = loadTextContent('../k8s/ksm.yaml')
var functionsYaml = loadTextContent('../k8s/functions.yaml')
var alertruleYaml = loadTextContent('../k8s/sample-alertrule.yaml')
var demoAppYaml = loadTextContent('../k8s/demo-app.yaml')
var amaMetricsSettingsYaml = loadTextContent('../k8s/ama-metrics-settings.yaml')

resource applyK8sManifests 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'apply-k8s-manifests'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deployerIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.63.0'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    forceUpdateTag: forceScriptRerun != '' ? forceScriptRerun : 'stable'
    environmentVariables: [
      { name: 'AKS_CLUSTER', value: aksClusterName }
      { name: 'AKS_RG', value: resourceGroup().name }
      { name: 'ADX_URL', value: adxUri }
      { name: 'CLIENT_ID', value: adxMonClientId }
      { name: 'CLUSTER_NAME', value: clusterName }
      { name: 'REGION', value: region }
      { name: 'CRDS_YAML', value: crdsYaml }
      { name: 'INGESTOR_YAML', value: ingestorYaml }
      { name: 'COLLECTOR_YAML', value: collectorYaml }
      { name: 'KSM_YAML', value: ksmYaml }
      { name: 'FUNCTIONS_YAML', value: functionsYaml }
      { name: 'ALERTRULE_YAML', value: alertruleYaml }
      { name: 'DEMOAPP_YAML', value: demoAppYaml }
      { name: 'AMA_METRICS_SETTINGS_YAML', value: amaMetricsSettingsYaml }
    ]
    scriptContent: '''
      set -e

      echo "=== Installing kubectl ==="
      az aks install-cli 2>/dev/null || true

      echo "=== Getting AKS credentials ==="
      az aks get-credentials -n "$AKS_CLUSTER" -g "$AKS_RG" --overwrite-existing --admin

      echo "=== Applying CRDs ==="
      echo "$CRDS_YAML" | kubectl apply -f -

      echo "=== Waiting for CRDs to be established ==="
      kubectl wait --for condition=established --timeout=60s \
        crd/functions.adx-mon.azure.com \
        crd/alertrules.adx-mon.azure.com \
        crd/managementcommands.adx-mon.azure.com

      echo "=== Creating namespaces ==="
      kubectl create namespace adx-mon --dry-run=client -o yaml | kubectl apply -f -
      kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

      echo "=== Applying ingestor ==="
      echo "$INGESTOR_YAML" | sed "s|__ADX_URL__|$ADX_URL|g; s|__CLIENT_ID__|$CLIENT_ID|g; s|__CLUSTER_NAME__|$CLUSTER_NAME|g; s|__REGION__|$REGION|g" | kubectl apply -f -

      echo "=== Applying collector ==="
      echo "$COLLECTOR_YAML" | sed "s|__ADX_URL__|$ADX_URL|g; s|__CLIENT_ID__|$CLIENT_ID|g; s|__CLUSTER_NAME__|$CLUSTER_NAME|g; s|__REGION__|$REGION|g" | kubectl apply -f -

      echo "=== Applying kube-state-metrics ==="
      echo "$KSM_YAML" | sed "s|__ADX_URL__|$ADX_URL|g; s|__CLIENT_ID__|$CLIENT_ID|g; s|__CLUSTER_NAME__|$CLUSTER_NAME|g; s|__REGION__|$REGION|g" | kubectl apply -f -

      echo "=== Applying functions ==="
      echo "$FUNCTIONS_YAML" | sed "s|__ADX_URL__|$ADX_URL|g; s|__CLIENT_ID__|$CLIENT_ID|g; s|__CLUSTER_NAME__|$CLUSTER_NAME|g; s|__REGION__|$REGION|g" | kubectl apply -f -

      echo "=== Applying sample alert rule ==="
      echo "$ALERTRULE_YAML" | sed "s|__ADX_URL__|$ADX_URL|g; s|__CLIENT_ID__|$CLIENT_ID|g; s|__CLUSTER_NAME__|$CLUSTER_NAME|g; s|__REGION__|$REGION|g" | kubectl apply -f -

      echo "=== Applying demo app ==="
      echo "$DEMOAPP_YAML" | kubectl apply -f -

      echo "=== Applying ama-metrics ConfigMap (full Prometheus profile + pod-annotation scraping) ==="
      echo "$AMA_METRICS_SETTINGS_YAML" | kubectl apply -f -

      echo "=== Annotating CoreDNS for log capture ==="
      kubectl patch deployment coredns -n kube-system --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"adx-mon/scrape":"true","adx-mon/port":"9153","adx-mon/path":"/metrics","adx-mon/log-destination":"Logs:CoreDNS","adx-mon/log-parsers":""}}}}}' || true

      echo "=== Deployment complete. Pod status: ==="
      kubectl get pods -n adx-mon
      kubectl get pods -n monitoring
    '''
  }
}
