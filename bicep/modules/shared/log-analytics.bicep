// Shared SIEM backing store for the detection path.
//
// The sim-plane network tap writes UAV*_CL telemetry here (append-only, via a
// Data Collection Rule); the SOC plane reads it with Sentinel analytics rules
// and detects the red attack INDEPENDENTLY — red is never in the detection
// path. This workspace is the decoupling point: there is no direct sim<->soc
// network peering. Both planes meet only at this managed workspace over the
// Azure backbone.
//
// Append-only is enforced at the data layer: the tap's managed identity gets
// only the Monitoring Metrics Publisher role on the DCR (ingest, no read/delete);
// the SOC identity gets Log Analytics Reader. Those role assignments and the DCR
// + custom-table schema land alongside this module (see "Not yet coded" in the
// repo README) — this file provisions the workspace itself.

@description('Location for the shared workspace.')
param location string

@description('Workspace name.')
param workspaceName string = 'dah-shared-law'

@description('Retention in days for ingested telemetry.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Daily ingestion cap in GB (cost guard; -1 = uncapped).')
param dailyQuotaGb int = 1

param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      // Reads route through DCR/table RBAC, not shared keys.
      disableLocalAuth: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output customerId string = workspace.properties.customerId
