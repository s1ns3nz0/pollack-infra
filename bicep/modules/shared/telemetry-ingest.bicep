// Detection-path ingestion seam: the sim-plane network tap writes UAV*_CL
// telemetry into the shared workspace through a Data Collection Rule (DCR) via a
// Data Collection Endpoint (DCE). Append-only is enforced at the data layer:
//   - the tap identity gets Monitoring Metrics Publisher ON THE DCR ONLY
//     (ingest; no read, no delete)
//   - the SOC identity gets Log Analytics Reader on the workspace (query; no write)
// Red is never granted anything here — it is not in the detection path.
//
// Custom tables mirror the rows produced by redteam_core/bridge/telemetry_tap.py
// (the four the tap actually emits). Extend as the tap grows.

@description('Location.')
param location string

@description('Existing shared Log Analytics workspace name.')
param workspaceName string

@description('Resource ID of the shared workspace (for DCR destination).')
param workspaceId string

@description('Principal ID of the sim-plane tap identity. Empty = skip its role assignment.')
param tapPrincipalId string = ''

@description('Principal ID of the SOC reader identity. Empty = skip its role assignment.')
param socReaderPrincipalId string = ''

param tags object

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'

// Column sets derived from telemetry_tap.py / soc_feeder.py. TimeGenerated is
// mandatory for any Log Analytics custom table.
var tableSchemas = [
  {
    name: 'UAVOperator_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'SourceSystemId', type: 'int' }
      { name: 'Command', type: 'int' }
      { name: 'SourceSystemIdAnomaly', type: 'boolean' }
      { name: 'Param1', type: 'real' }
    ]
  }
  {
    name: 'UAVDatalinkConn_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'LocalPort', type: 'int' }
      { name: 'PeerIp', type: 'string' }
      { name: 'State', type: 'string' }
    ]
  }
  {
    name: 'UAVConfigAudit_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'ParamId', type: 'string' }
      { name: 'ParamValueAfter', type: 'real' }
    ]
  }
  {
    name: 'UAVTelemetry_CL'
    columns: [
      { name: 'TimeGenerated', type: 'datetime' }
      { name: 'PosHorizVariance', type: 'real' }
      { name: 'FixType', type: 'int' }
    ]
  }
]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource tables 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = [
  for t in tableSchemas: {
    parent: workspace
    name: t.name
    properties: {
      schema: {
        name: t.name
        columns: t.columns
      }
      plan: 'Analytics'
    }
  }
]

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: 'dah-shared-dce'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dah-uav-telemetry-dcr'
  location: location
  tags: tags
  dependsOn: [
    tables
  ]
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-UAVOperator_CL': {
        columns: tableSchemas[0].columns
      }
      'Custom-UAVDatalinkConn_CL': {
        columns: tableSchemas[1].columns
      }
      'Custom-UAVConfigAudit_CL': {
        columns: tableSchemas[2].columns
      }
      'Custom-UAVTelemetry_CL': {
        columns: tableSchemas[3].columns
      }
    }
    destinations: {
      logAnalytics: [
        {
          name: 'sharedWorkspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: [
      for t in tableSchemas: {
        streams: [
          'Custom-${t.name}'
        ]
        destinations: [
          'sharedWorkspace'
        ]
        transformKql: 'source'
        outputStream: 'Custom-${t.name}'
      }
    ]
  }
}

// Tap: ingest-only on the DCR (append-only enforcement point).
resource tapIngest 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(tapPrincipalId)) {
  name: guid(dcr.id, tapPrincipalId, monitoringMetricsPublisherRoleId)
  scope: dcr
  properties: {
    principalId: tapPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

// SOC: read-only on the workspace.
resource socRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(socReaderPrincipalId)) {
  name: guid(workspace.id, socReaderPrincipalId, logAnalyticsReaderRoleId)
  scope: workspace
  properties: {
    principalId: socReaderPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
  }
}

output dcrId string = dcr.id
output dceLogsIngestionEndpoint string = dce.properties.logsIngestion.endpoint
output dcrImmutableId string = dcr.properties.immutableId
