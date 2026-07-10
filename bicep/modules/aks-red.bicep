param location string
param aksSubnetId string
param nodeResourceGroup string
param authorizedIpRanges array
param tags object

@description('VM size for the red AKS system node pool.')
param systemNodeSize string = 'Standard_D4s_v5'

@description('Node count for the red AKS system node pool.')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 1

@description('VM size for the red-agent workload node pool.')
param userNodeSize string = 'Standard_D4s_v5'

@description('Node count for the red-agent workload node pool.')
@minValue(1)
@maxValue(5)
param userNodeCount int = 1

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: 'dah-red-aks'
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: 'dah-red-aks'
    nodeResourceGroup: nodeResourceGroup
    disableLocalAccounts: true
    enableRBAC: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    apiServerAccessProfile: {
      enablePrivateCluster: false
      authorizedIPRanges: authorizedIpRanges
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
      outboundType: 'userDefinedRouting'
    }
    agentPoolProfiles: [
      {
        name: 'npsystem'
        mode: 'System'
        count: systemNodeCount
        vmSize: systemNodeSize
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
      }
      {
        name: 'npred'
        mode: 'User'
        count: userNodeCount
        vmSize: userNodeSize
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        nodeTaints: [
          'workload=red-agent:NoSchedule'
        ]
        nodeLabels: {
          workload: 'red-agent'
        }
      }
    ]
  }
}

output aksName string = aks.name
output aksId string = aks.id
output kubeletPrincipalId string = aks.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
