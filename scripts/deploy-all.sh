#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/quota.sh
source "$SCRIPT_DIR/lib/quota.sh"
# shellcheck source=lib/aoai.sh
source "$SCRIPT_DIR/lib/aoai.sh"
cd "$REPO_ROOT"

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
RED_RG="${RED_RG:-dah-red-rg}"
RED_AKS_NAME="${RED_AKS_NAME:-dah-red-aks}"
RED_PARAM_FILE="${RED_PARAM_FILE:-bicep/params/lab.bicepparam}"
DEPLOY_SIM_VM="${DEPLOY_SIM_VM:-false}"   # VM host needs SSH key + allowed IP
SIM_NODE_SIZE="${SIM_NODE_SIZE:-Standard_D4s_v5}"
SIM_NODE_COUNT="${SIM_NODE_COUNT:-1}"
SOC_NODE_SIZE="${SOC_NODE_SIZE:-Standard_D4s_v5}"
SOC_NODE_COUNT="${SOC_NODE_COUNT:-1}"
RED_SYSTEM_NODE_SIZE="${RED_SYSTEM_NODE_SIZE:-Standard_D2s_v5}"
RED_SYSTEM_NODE_COUNT="${RED_SYSTEM_NODE_COUNT:-1}"
RED_USER_NODE_SIZE="${RED_USER_NODE_SIZE:-Standard_D2s_v5}"
RED_USER_NODE_COUNT="${RED_USER_NODE_COUNT:-1}"
QUOTA_WAIT_TIMEOUT="${QUOTA_WAIT_TIMEOUT:-600}"
QUOTA_POLL_SECONDS="${QUOTA_POLL_SECONDS:-15}"

SIM_TOTAL_NODE_COUNT=$((SIM_NODE_COUNT * 3))
DESIRED_VCPUS="$(
  topology_vcpus \
    "$SIM_NODE_SIZE" "$SIM_TOTAL_NODE_COUNT" \
    "$SOC_NODE_SIZE" "$SOC_NODE_COUNT" \
    "$RED_SYSTEM_NODE_SIZE" "$RED_SYSTEM_NODE_COUNT" \
    "$RED_USER_NODE_SIZE" "$RED_USER_NODE_COUNT"
)"
REGIONAL_VCPU_LIMIT="$(
  az vm list-usage --location "$LOCATION" \
    --query "[?name.value=='cores'].limit | [0]" -o tsv
)"

if [[ ! "$REGIONAL_VCPU_LIMIT" =~ ^[0-9]+$ ]]; then
  echo "Unable to read regional vCPU limit for $LOCATION" >&2
  exit 1
fi
if (( DESIRED_VCPUS > REGIONAL_VCPU_LIMIT )); then
  echo "Configured topology exceeds regional vCPU quota: desired=$DESIRED_VCPUS limit=$REGIONAL_VCPU_LIMIT location=$LOCATION" >&2
  exit 1
fi
echo "quota plan: desired=$DESIRED_VCPUS limit=$REGIONAL_VCPU_LIMIT location=$LOCATION"

echo "== 1/5 data (Log Analytics + Sentinel) =="
az group create -n "$DATA_RG" -l "$LOCATION" -o none
az deployment group create -g "$DATA_RG" -n data-mvp -f bicep/planes/data.bicep -o none
WORKSPACE_ID="$(az deployment group show -g "$DATA_RG" -n data-mvp --query properties.outputs.workspaceId.value -o tsv)"
echo "workspaceId=$WORKSPACE_ID"

echo "== 2/5 aoai (Azure OpenAI) =="
az group create -n "$SOC_RG" -l "$LOCATION" -o none
recover_deleted_aoai_accounts "$SOC_RG" "$LOCATION"
az deployment group create -g "$SOC_RG" -n aoai-mvp -f bicep/planes/aoai.bicep -o none
# aoai 계정명/엔드포인트를 red 배포로 전달(red 는 kagent OpenAI 역할할당에 이 계정을 참조).
AOAI_ACCT="$(az deployment group show -g "$SOC_RG" -n aoai-mvp --query properties.outputs.accountName.value -o tsv)"
AOAI_ENDPOINT="$(az deployment group show -g "$SOC_RG" -n aoai-mvp --query properties.outputs.endpoint.value -o tsv)"
echo "aoai account=$AOAI_ACCT"

echo "== 3/5 sim-aks (dah-sim-aks) =="
az group create -n "$SIM_RG" -l "$LOCATION" -o none
az deployment group create -g "$SIM_RG" -n sim-aks -f bicep/planes/sim-aks.bicep \
  -p workspaceId="$WORKSPACE_ID" \
  nodeSize="$SIM_NODE_SIZE" \
  systemNodeCount="$SIM_NODE_COUNT" \
  sitlNodeCount="$SIM_NODE_COUNT" \
  satcomNodeCount="$SIM_NODE_COUNT" -o none

echo "== 4/5 soc (dah-soc-aks) =="
az deployment group create -g "$SOC_RG" -n soc-mvp -f bicep/planes/soc.bicep \
  -p workspaceId="$WORKSPACE_ID" \
  systemNodeSize="$SOC_NODE_SIZE" \
  systemNodeCount="$SOC_NODE_COUNT" -o none

echo "== 5/5 red plane (subscription-scope) =="
RED_VCPUS=$((
  $(vm_size_vcpus "$RED_SYSTEM_NODE_SIZE") * RED_SYSTEM_NODE_COUNT +
  $(vm_size_vcpus "$RED_USER_NODE_SIZE") * RED_USER_NODE_COUNT
))
EXISTING_RED_AKS_ID="$(
  az aks show -g "$RED_RG" -n "$RED_AKS_NAME" --query id -o tsv 2>/dev/null || true
)"
if [[ "$(red_capacity_wait_required "$EXISTING_RED_AKS_ID")" == true ]]; then
  wait_for_regional_vcpu_capacity \
    "$LOCATION" "$RED_VCPUS" "$QUOTA_WAIT_TIMEOUT" "$QUOTA_POLL_SECONDS"
else
  echo "red AKS already exists; no additional regional vCPU capacity is required"
fi
az deployment sub create --location "$LOCATION" \
  --template-file bicep/main.bicep --parameters "$RED_PARAM_FILE" \
  azureOpenAIResourceGroupName="$SOC_RG" \
  azureOpenAIAccountName="$AOAI_ACCT" \
  azureOpenAIEndpoint="$AOAI_ENDPOINT" \
  redSystemNodeSize="$RED_SYSTEM_NODE_SIZE" \
  redSystemNodeCount="$RED_SYSTEM_NODE_COUNT" \
  redUserNodeSize="$RED_USER_NODE_SIZE" \
  redUserNodeCount="$RED_USER_NODE_COUNT" \
  --query '{state:properties.provisioningState}' -o json

if [ "$DEPLOY_SIM_VM" = "true" ]; then
  : "${SIM_VM_SSH_KEY:?set SIM_VM_SSH_KEY to your SSH public key}"
  : "${SIM_VM_ALLOWED_IP:?set SIM_VM_ALLOWED_IP to your public IP}"
  echo "== opt: sim-vm host =="
  az deployment group create -g "$SIM_RG" -n sim-vm -f bicep/planes/sim-vm.bicep \
    -p adminPublicKey="$SIM_VM_SSH_KEY" allowedSourceIp="$SIM_VM_ALLOWED_IP" -o none
fi

echo "== done. all planes provisioned. =="
