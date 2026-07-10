using '../main.bicep'

param location = 'koreacentral'
param environment = 'lab'

param uniqueSuffix = 'r0710a'

param authorizedIpRanges = [
  '203.236.101.248/32'
]

// Egress FQDNs allowed through dah-red-fw in addition to the AKS/registry
// baseline. Add approved sim target endpoints here as they are confirmed.
param allowedEgressFqdns = [
  '*.openai.azure.com'
  '*.cognitiveservices.azure.com'
  'cr.kagent.dev'
  'ghcr.io'
  '*.ghcr.io'
  'pkg-containers.githubusercontent.com'
  '*.pkg-containers.githubusercontent.com'
  'docker.io'
  '*.docker.io'
  'registry-1.docker.io'
  'auth.docker.io'
  'production.cloudflare.docker.com'
]

param aksRbacClusterAdminObjectIds = [
  '8b7bc0ba-9019-4ca0-924e-821e8872f2ea'
]

// Keep the complete two-pool red topology within the lab subscription's
// 20-vCPU Korea Central quota.
param redSystemNodeSize = 'Standard_D2s_v5'
param redSystemNodeCount = 1
param redUserNodeSize = 'Standard_D2s_v5'
param redUserNodeCount = 1

param azureOpenAIResourceGroupName = 'dah-soc-rg'
param azureOpenAIAccountName = 'dah-aoai-kzjpmnfl4iwvg'
param azureOpenAIEndpoint = 'https://dah-aoai-kzjpmnfl4iwvg.openai.azure.com/'
param azureOpenAIDeploymentName = 'gpt-4o-soc'

// Workload Identity federation subjects. Must match the red overlay manifests.
param toolserverNamespace = 'red-agent'
param toolserverServiceAccount = 'fried-pollack-toolserver'
param kagentNamespace = 'kagent'
param kagentServiceAccount = 'kagent-controller'

// SOC is out of scope for this session.
param enableSoc = false

// Lab: keep immutability off so `az group delete` tears the plane down cleanly.
// Object-level immutability blocks storage-account (and thus RG) deletion.
param enableImmutableArtifacts = false

// Fill after sim/soc VNet resource IDs are confirmed.
param simVnetResourceId = ''
param socVnetResourceId = ''
