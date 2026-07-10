#!/usr/bin/env bash
set -euo pipefail

# Full-stack range deploy in dependency order. Consolidated from uav-sim-env
# (data/aoai/sim/soc/vm, RG-scope) + red plane (main.bicep, subscription-scope).
#
#   data (Log Analytics + Sentinel)  →  workspaceId
#     ├─ aoai  (Azure OpenAI gpt-4o-soc → gpt-4o-mini)
#     ├─ sim-aks   (needs workspaceId)
#     ├─ soc       (needs workspaceId)
#     └─ red   (subscription-scope AKS + firewall + shared seam)
#   sim-vm (uav-sim-env host) — opt-in (needs SSH key + your IP).

LOCATION="${LOCATION:-koreacentral}"
DATA_RG="${DATA_RG:-dah-data-rg}"
SOC_RG="${SOC_RG:-dah-soc-rg}"
SIM_RG="${SIM_RG:-dah-sim-rg}"
RED_PARAM_FILE="${RED_PARAM_FILE:-bicep/params/lab.bicepparam}"
DEPLOY_SIM_VM="${DEPLOY_SIM_VM:-false}"   # VM host needs SSH key + allowed IP

echo "== 1/5 data (Log Analytics + Sentinel) =="
az group create -n "$DATA_RG" -l "$LOCATION" -o none
az deployment group create -g "$DATA_RG" -n data-mvp -f bicep/planes/data.bicep -o none
WORKSPACE_ID="$(az deployment group show -g "$DATA_RG" -n data-mvp --query properties.outputs.workspaceId.value -o tsv)"
echo "workspaceId=$WORKSPACE_ID"

echo "== 2/5 aoai (Azure OpenAI) =="
az group create -n "$SOC_RG" -l "$LOCATION" -o none
az deployment group create -g "$SOC_RG" -n aoai-mvp -f bicep/planes/aoai.bicep -o none
# aoai 계정명/엔드포인트를 red 배포로 전달(red 는 kagent OpenAI 역할할당에 이 계정을 참조).
AOAI_ACCT="$(az deployment group show -g "$SOC_RG" -n aoai-mvp --query properties.outputs.accountName.value -o tsv)"
AOAI_ENDPOINT="$(az deployment group show -g "$SOC_RG" -n aoai-mvp --query properties.outputs.endpoint.value -o tsv)"
echo "aoai account=$AOAI_ACCT"

echo "== 3/5 sim-aks (dah-sim-aks) =="
az group create -n "$SIM_RG" -l "$LOCATION" -o none
az deployment group create -g "$SIM_RG" -n sim-aks -f bicep/planes/sim-aks.bicep \
  -p workspaceId="$WORKSPACE_ID" -o none

echo "== 4/5 soc (dah-soc-aks) =="
az deployment group create -g "$SOC_RG" -n soc-mvp -f bicep/planes/soc.bicep \
  -p workspaceId="$WORKSPACE_ID" -o none

echo "== 5/5 red plane (subscription-scope) =="
az deployment sub create --location "$LOCATION" \
  --template-file bicep/main.bicep --parameters "$RED_PARAM_FILE" \
  azureOpenAIResourceGroupName="$SOC_RG" \
  azureOpenAIAccountName="$AOAI_ACCT" \
  azureOpenAIEndpoint="$AOAI_ENDPOINT" \
  --query '{state:properties.provisioningState}' -o json

if [ "$DEPLOY_SIM_VM" = "true" ]; then
  : "${SIM_VM_SSH_KEY:?set SIM_VM_SSH_KEY to your SSH public key}"
  : "${SIM_VM_ALLOWED_IP:?set SIM_VM_ALLOWED_IP to your public IP}"
  echo "== opt: sim-vm host =="
  az deployment group create -g "$SIM_RG" -n sim-vm -f bicep/planes/sim-vm.bicep \
    -p adminPublicKey="$SIM_VM_SSH_KEY" allowedSourceIp="$SIM_VM_ALLOWED_IP" -o none
fi

echo "== done. all planes provisioned. =="
