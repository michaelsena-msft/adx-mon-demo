@description('The name of the AKS managed cluster.')
param clusterName string

@description('The Azure region where the AKS cluster will be deployed.')
param location string

@description('The VM size for the system node pool.')
param nodeVmSize string = 'Standard_D4s_v3'

@description('The number of nodes in the system node pool.')
param nodeCount int = 2

@description('The Kubernetes version for the AKS cluster.')
param kubernetesVersion string = '1.33'

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
      upgradeChannel: 'patch'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osDiskType: 'Managed'
        mode: 'System'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      advancedNetworking: {
        enabled: true
        observability: {
          enabled: true
        }
      }
    }
  }
}

@description('The name of the AKS cluster.')
output aksName string = aks.name

@description('The resource ID of the AKS cluster.')
output aksId string = aks.id

@description('The OIDC issuer URL of the AKS cluster.')
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
