@description('Name of the ADX cluster.')
param clusterName string

@description('Azure region for all resources.')
param location string

@description('SKU name for the ADX cluster compute.')
param skuName string = 'Standard_E2ads_v5'

@description('SKU capacity (instance count) for the ADX cluster.')
param skuCapacity int = 2

resource cluster 'Microsoft.Kusto/clusters@2024-04-13' = {
  name: clusterName
  location: location
  sku: {
    name: skuName
    tier: 'Standard'
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    engineType: 'V3'
    // Streaming ingestion is not required — adx-mon uses queued ingestion.
    // https://learn.microsoft.com/en-us/azure/data-explorer/ingest-data-overview
    enableStreamingIngest: false
    enablePurge: true
  }
}

resource metricsDb 'Microsoft.Kusto/clusters/databases@2024-04-13' = {
  name: 'Metrics'
  parent: cluster
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P365D'
    hotCachePeriod: 'P31D'
  }
}

resource logsDb 'Microsoft.Kusto/clusters/databases@2024-04-13' = {
  name: 'Logs'
  parent: cluster
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P365D'
    hotCachePeriod: 'P31D'
  }
}

// Batching and streaming policies are intentionally omitted:
// - adx-mon uses queued ingestion, not streaming — streaming policies are unnecessary.
// - ADX defaults (5 min / 1 GB / 1000 blobs) are appropriate for queued ingestion.
//   Aggressive batching (e.g., 30s) creates excessive operations on small clusters.
// - prom_delta() is auto-deployed by adx-mon's ingestor; no Bicep script needed.
// Ref: https://learn.microsoft.com/en-us/kusto/management/batching-policy

output adxName string = cluster.name
output adxUri string = cluster.properties.uri
