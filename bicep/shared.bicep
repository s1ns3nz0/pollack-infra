targetScope = 'subscription'

// Cross-plane seam deployment: resources that belong to no single plane.
// Currently the shared SIEM workspace (detection-path decoupling point).
// The DCR + UAV*_CL custom-table schema, the tap/SOC role assignments, and any
// peering hardening land here next (see README "Not yet coded").

@description('Location for shared resources.')
param location string = 'koreacentral'

@description('Environment name for tags.')
param environment string = 'lab'

@description('Resource group for shared cross-plane resources.')
param sharedResourceGroupName string = 'dah-shared-rg'

@description('Daily ingestion cap in GB for the shared workspace (cost guard).')
param dailyQuotaGb int = 1

var commonTags = {
  project: 'dah'
  plane: 'shared'
  environment: environment
  data_classification: 'restricted'
  managed_by: 'bicep'
}

resource sharedRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: sharedResourceGroupName
  location: location
  tags: commonTags
}

module law 'modules/shared/log-analytics.bicep' = {
  name: 'shared-log-analytics'
  scope: resourceGroup(sharedResourceGroupName)
  dependsOn: [
    sharedRg
  ]
  params: {
    location: location
    dailyQuotaGb: dailyQuotaGb
    tags: commonTags
  }
}

output sharedResourceGroupName string = sharedResourceGroupName
output workspaceId string = law.outputs.workspaceId
output workspaceName string = law.outputs.workspaceName
