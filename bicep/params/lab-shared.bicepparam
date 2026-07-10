using '../shared.bicep'

param location = 'koreacentral'
param environment = 'lab'
param sharedResourceGroupName = 'dah-shared-rg'

// Cost guard: cap telemetry ingestion. Raise for a live range with real tap volume.
param dailyQuotaGb = 1
