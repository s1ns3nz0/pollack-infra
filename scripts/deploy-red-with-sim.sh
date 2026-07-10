#!/usr/bin/env bash
set -euo pipefail

# Red plane (subscription-scope) + optional sim range (RG-scope planes/sim-aks).
# For the full range stack (data/aoai/sim/soc/red) use scripts/deploy-all.sh.
# Judge Path B (red-focused) runs this with DEPLOY_SIM=false.

LOCATION="${LOCATION:-koreacentral}"
RED_DEPLOYMENT_NAME="${RED_DEPLOYMENT_NAME:-red-plane-current}"
RED_RESOURCE_GROUP="${RED_RESOURCE_GROUP:-dah-red-rg}"
SIM_RESOURCE_GROUP="${SIM_RESOURCE_GROUP:-dah-sim-rg}"
DATA_RESOURCE_GROUP="${DATA_RESOURCE_GROUP:-dah-data-rg}"
SIM_AKS_NAME="${SIM_AKS_NAME:-dah-sim-aks}"
SIM_VNET_NAME="${SIM_VNET_NAME:-dah-sim-vnet}"
DATA_WORKSPACE_NAME="${DATA_WORKSPACE_NAME:-dah-data-law}"
DEPLOY_SIM="${DEPLOY_SIM:-false}"

# Path B (reviewer's own subscription): point at the judge template.
RED_PARAM_FILE="${RED_PARAM_FILE:-bicep/params/lab.bicepparam}"

sim_aks_exists() {
  az aks show -g "$SIM_RESOURCE_GROUP" -n "$SIM_AKS_NAME" --query id -o tsv >/dev/null 2>&1
}
sim_vnet_id() {
  az network vnet show -g "$SIM_RESOURCE_GROUP" -n "$SIM_VNET_NAME" --query id -o tsv 2>/dev/null || true
}

if [ "$DEPLOY_SIM" = "true" ]; then
  if sim_aks_exists; then
    echo "sim AKS exists in $SIM_RESOURCE_GROUP/$SIM_AKS_NAME; skipping sim deployment"
  else
    echo "sim AKS not found; deploying sim plane (planes/sim-aks.bicep, RG-scope)"
    WORKSPACE_ID="$(az monitor log-analytics workspace show \
      -g "$DATA_RESOURCE_GROUP" -n "$DATA_WORKSPACE_NAME" --query id -o tsv 2>/dev/null || true)"
    az group create -n "$SIM_RESOURCE_GROUP" -l "$LOCATION" -o none
    az deployment group create -g "$SIM_RESOURCE_GROUP" -n sim-aks \
      -f bicep/planes/sim-aks.bicep -p workspaceId="$WORKSPACE_ID" -o none
  fi
else
  echo "DEPLOY_SIM=false; skipping sim (full stack: scripts/deploy-all.sh)"
fi

SIM_VNET_ID="$(sim_vnet_id)"
if [ -n "$SIM_VNET_ID" ]; then
  echo "using sim VNet for red peering: $SIM_VNET_ID"
  az deployment sub create --name "$RED_DEPLOYMENT_NAME" --location "$LOCATION" \
    --template-file bicep/main.bicep \
    --parameters "$RED_PARAM_FILE" simVnetResourceId="$SIM_VNET_ID" \
    --query '{state:properties.provisioningState,outputs:properties.outputs}' --output json
else
  echo "sim VNet not found; deploying red without sim peering"
  az deployment sub create --name "$RED_DEPLOYMENT_NAME" --location "$LOCATION" \
    --template-file bicep/main.bicep --parameters "$RED_PARAM_FILE" \
    --query '{state:properties.provisioningState,outputs:properties.outputs}' --output json
fi
