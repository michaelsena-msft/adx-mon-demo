@description('Name of the ADX cluster.')
param clusterName string

@description('Azure region for all resources.')
param location string

@description('SKU name for the ADX cluster compute.')
param skuName string = 'Standard_E2ads_v5'

@description('SKU capacity (instance count) for the ADX cluster.')
param skuCapacity int = 2

@description('Force update tag for Kusto scripts.')
param forceUpdateTag string = utcNow()

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
    enableStreamingIngest: true
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

resource metricsBatchingPolicy 'Microsoft.Kusto/clusters/databases/scripts@2024-04-13' = {
  name: 'metricsBatchingPolicy'
  parent: metricsDb
  properties: {
    #disable-next-line use-secure-value-for-secure-inputs // Kusto management command, not a secret
    scriptContent: '.alter database Metrics policy ingestionbatching @\'{"MaximumBatchingTimeSpan":"00:00:30","MaximumNumberOfItems":500,"MaximumRawDataSizeMB":1024}\''
    continueOnErrors: false
    forceUpdateTag: forceUpdateTag
  }
}

resource logsBatchingPolicy 'Microsoft.Kusto/clusters/databases/scripts@2024-04-13' = {
  name: 'logsBatchingPolicy'
  parent: logsDb
  properties: {
    #disable-next-line use-secure-value-for-secure-inputs // Kusto management command, not a secret
    scriptContent: '.alter database Logs policy ingestionbatching @\'{"MaximumBatchingTimeSpan":"00:05:00","MaximumNumberOfItems":500,"MaximumRawDataSizeMB":1024}\''
    continueOnErrors: false
    forceUpdateTag: forceUpdateTag
  }
}

resource promDeltaFunction 'Microsoft.Kusto/clusters/databases/scripts@2024-04-13' = {
  name: 'promDeltaFunction'
  parent: metricsDb
  properties: {
    #disable-next-line use-secure-value-for-secure-inputs // Kusto function definition, not a secret
    scriptContent: '.create-or-alter function with (folder=\'adx-mon\', docstring=\'Calculates delta for Prometheus counters\') prom_delta(T:(Timestamp:datetime, SeriesId:long, Labels:dynamic, Value:real)) {\n  T\n  | order by SeriesId, Timestamp asc\n  | extend prev_val = prev(Value), prev_id = prev(SeriesId)\n  | where SeriesId == prev_id\n  | extend delta = iff(Value >= prev_val, Value - prev_val, Value)\n  | where delta >= 0\n  | project-away prev_val, prev_id\n}'
    continueOnErrors: false
    forceUpdateTag: forceUpdateTag
  }
  dependsOn: [
    metricsBatchingPolicy
  ]
}

output adxName string = cluster.name
output adxId string = cluster.id
output adxUri string = cluster.properties.uri
output adxIdentityPrincipalId string = cluster.identity.principalId
