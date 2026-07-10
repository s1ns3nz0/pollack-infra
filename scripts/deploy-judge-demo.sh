#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/judge-demo.sh
source "$SCRIPT_DIR/lib/judge-demo.sh"

APP_REPO="${APP_REPO:-$REPO_ROOT/../fried-pollack-ai}"
SOC_REPO="${SOC_REPO:-$REPO_ROOT/../pollack-ai}"
TOOLSERVER_TAG="${TOOLSERVER_TAG:-judge-$(git -C "$APP_REPO" rev-parse --short HEAD 2>/dev/null || printf current)}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"
DATA_RG="${DATA_RG:-dah-data-rg}"
SOC_RG="${SOC_RG:-dah-soc-rg}"
SIM_RG="${SIM_RG:-dah-sim-rg}"
RED_RG="${RED_RG:-dah-red-rg}"
SIM_AKS="${SIM_AKS:-dah-sim-aks}"
SOC_AKS="${SOC_AKS:-dah-soc-aks}"
RED_AKS="${RED_AKS:-dah-red-aks}"

record_stage() {
  if [[ -n "${JUDGE_DEMO_COMMAND_LOG:-}" ]]; then
    printf '%s\n' "$1" >>"$JUDGE_DEMO_COMMAND_LOG"
  fi
}

if [[ "${JUDGE_DEMO_TEST_MODE:-false}" == true ]]; then
  for stage in deploy-all discover build-image bootstrap generate-kpi start-dashboards verify print-summary; do
    record_stage "$stage"
  done
  exit 0
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

for command_name in az kubectl kubelogin helm curl python git; do
  require_command "$command_name"
done
[[ -f "$APP_REPO/scripts/bootstrap-red-agent.sh" ]] || {
  echo "fried-pollack-ai checkout not found at $APP_REPO (override APP_REPO)" >&2
  exit 1
}
[[ -f "$SOC_REPO/app/dashboard.py" ]] || {
  echo "pollack-ai checkout not found at $SOC_REPO (override SOC_REPO)" >&2
  exit 1
}
(cd "$SOC_REPO" && python -c 'import fastapi, uvicorn, app.dashboard') || {
  echo "pollack-ai dashboard dependencies are missing; run: python -m pip install -e '$SOC_REPO'" >&2
  exit 1
}

ensure_runtime_dir
DEPLOY_LOG="$JUDGE_DEMO_RUNTIME_DIR/deploy-all.log"
BOOTSTRAP_LOG="$JUDGE_DEMO_RUNTIME_DIR/bootstrap-red-agent.log"
KUBECONFIG_FILE="$JUDGE_DEMO_RUNTIME_DIR/red-kubeconfig"

echo "== Judge demo: deploy full Azure stack =="
record_stage deploy-all
(cd "$REPO_ROOT" && bash scripts/deploy-all.sh) 2>&1 | tee "$DEPLOY_LOG"

echo "== Judge demo: discover deployed resources =="
record_stage discover
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
WORKSPACE_ID="$(az deployment group show -g "$DATA_RG" -n data-mvp --query properties.outputs.workspaceId.value -o tsv)"
AOAI_ACCOUNT="$(az deployment group show -g "$SOC_RG" -n aoai-mvp --query properties.outputs.accountName.value -o tsv)"
AOAI_ID="$(az cognitiveservices account show -g "$SOC_RG" -n "$AOAI_ACCOUNT" --query id -o tsv)"
RED_ACR_LOGIN_SERVER="$(az deployment sub show -n main --query properties.outputs.redAcrLoginServer.value -o tsv)"
RED_ACR_NAME="${RED_ACR_LOGIN_SERVER%%.*}"
RED_STORAGE_NAME="$(az deployment sub show -n main --query properties.outputs.redStorageName.value -o tsv)"
RED_ACR_ID="$(az acr show -g "$RED_RG" -n "$RED_ACR_NAME" --query id -o tsv)"
RED_STORAGE_ID="$(az storage account show -g "$RED_RG" -n "$RED_STORAGE_NAME" --query id -o tsv)"
SIM_AKS_ID="$(az aks show -g "$SIM_RG" -n "$SIM_AKS" --query id -o tsv)"
SOC_AKS_ID="$(az aks show -g "$SOC_RG" -n "$SOC_AKS" --query id -o tsv)"
RED_AKS_ID="$(az aks show -g "$RED_RG" -n "$RED_AKS" --query id -o tsv)"

echo "== Judge demo: ensure immutable ToolServer image =="
record_stage build-image
IMAGE_EXISTS="$(
  az acr repository show-tags --name "$RED_ACR_NAME" --repository fried-pollack-ai \
    --query "[?@=='$TOOLSERVER_TAG'] | [0]" -o tsv 2>/dev/null || true
)"
if [[ "$IMAGE_EXISTS" == "$TOOLSERVER_TAG" ]]; then
  echo "Reusing $RED_ACR_LOGIN_SERVER/fried-pollack-ai:$TOOLSERVER_TAG"
else
  az acr build --registry "$RED_ACR_NAME" \
    --image "fried-pollack-ai:$TOOLSERVER_TAG" "$APP_REPO"
fi

rm -f "$KUBECONFIG_FILE"
az aks get-credentials -g "$RED_RG" -n "$RED_AKS" \
  --file "$KUBECONFIG_FILE" --overwrite-existing >/dev/null
chmod 600 "$KUBECONFIG_FILE"
kubelogin convert-kubeconfig --kubeconfig "$KUBECONFIG_FILE" --login azurecli
export KUBECONFIG="$KUBECONFIG_FILE"

echo "== Judge demo: bootstrap kagent and ToolServer =="
record_stage bootstrap
(
  cd "$APP_REPO"
  RED_RESOURCE_GROUP="$RED_RG" \
  RED_AKS_NAME="$RED_AKS" \
  RED_ACR_NAME="$RED_ACR_NAME" \
  AZURE_OPENAI_RESOURCE_GROUP="$SOC_RG" \
  AZURE_OPENAI_ACCOUNT_NAME="$AOAI_ACCOUNT" \
  TOOLSERVER_IMAGE="$RED_ACR_LOGIN_SERVER/fried-pollack-ai:$TOOLSERVER_TAG" \
  bash scripts/bootstrap-red-agent.sh
) 2>&1 | tee "$BOOTSTRAP_LOG"

if [[ "$INSTALL_ARGOCD" == true ]]; then
  echo "== Judge demo: install ArgoCD =="
  (
    cd "$APP_REPO"
    ACR_NAME="$RED_ACR_NAME" ACR_LOGIN_SERVER="$RED_ACR_LOGIN_SERVER" \
      bash scripts/bootstrap-argocd.sh
  )
  kubectl apply -f "$APP_REPO/deploy/argocd/root-app.yaml"
fi

echo "== Judge demo: generate KPI dashboard =="
record_stage generate-kpi
(cd "$APP_REPO" && python -m redteam_core.kpi.dashboard)

echo "== Judge demo: start local dashboards =="
record_stage start-dashboards
start_owned_process kagent-ui "$JUDGE_DEMO_RUNTIME_DIR/kagent-ui.log" \
  kubectl --kubeconfig "$KUBECONFIG_FILE" -n kagent port-forward \
  --address 127.0.0.1 service/kagent-ui 18080:8080
start_owned_process kpi-dashboard "$JUDGE_DEMO_RUNTIME_DIR/kpi-dashboard.log" \
  python -m http.server 18082 --bind 127.0.0.1 --directory "$APP_REPO/out"
start_owned_process cyber-staff-dashboard "$JUDGE_DEMO_RUNTIME_DIR/cyber-staff-dashboard.log" \
  sh -c 'cd "$1" && exec uvicorn app.dashboard:app --host 127.0.0.1 --port 18083' sh "$SOC_REPO"

ARGOCD_STATUS=SKIP
if kubectl -n argocd get service argocd-server >/dev/null 2>&1; then
  start_owned_process argocd "$JUDGE_DEMO_RUNTIME_DIR/argocd.log" \
    kubectl --kubeconfig "$KUBECONFIG_FILE" -n argocd port-forward \
    --address 127.0.0.1 service/argocd-server 18081:443
  ARGOCD_STATUS=READY
fi

echo "== Judge demo: verify runtime evidence =="
record_stage verify
for deployment_spec in \
  "$DATA_RG data-mvp" "$SOC_RG aoai-mvp" "$SIM_RG sim-aks" "$SOC_RG soc-mvp"; do
  read -r resource_group deployment_name <<<"$deployment_spec"
  [[ "$(az deployment group show -g "$resource_group" -n "$deployment_name" --query properties.provisioningState -o tsv)" == Succeeded ]]
done
[[ "$(az deployment sub show -n main --query properties.provisioningState -o tsv)" == Succeeded ]]
for aks_spec in "$SIM_RG $SIM_AKS" "$SOC_RG $SOC_AKS" "$RED_RG $RED_AKS"; do
  read -r resource_group cluster_name <<<"$aks_spec"
  [[ "$(az aks show -g "$resource_group" -n "$cluster_name" --query provisioningState -o tsv)" == Succeeded ]]
  [[ "$(az aks show -g "$resource_group" -n "$cluster_name" --query powerState.code -o tsv)" == Running ]]
done
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl -n kagent wait --for=condition=Available deployment --all --timeout=300s
kubectl -n fried-pollack wait --for=condition=Available deployment --all --timeout=300s
AGENT_READY="$(kubectl -n fried-pollack get agent fried-pollack-redteam-orchestrator -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
MCP_ACCEPTED="$(kubectl -n fried-pollack get remotemcpserver fried-pollack-toolserver -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')"
MCP_TOOLS="$(kubectl -n fried-pollack get remotemcpserver fried-pollack-toolserver -o jsonpath='{.status.discoveredTools[*].name}')"
[[ "$AGENT_READY" == True ]]
[[ "$MCP_ACCEPTED" == True ]]
[[ " $MCP_TOOLS " == *' run_engagement '* ]]
wait_for_http http://127.0.0.1:18080 false 60
wait_for_http http://127.0.0.1:18082/kpi-dashboard.html false 30
wait_for_http http://127.0.0.1:18083 false 30
curl -fsS http://127.0.0.1:18083 | grep -q '사이버 작전 참모 상황판'
if [[ "$ARGOCD_STATUS" == READY ]]; then
  wait_for_http https://127.0.0.1:18081 true 60
fi

record_stage print-summary
cat <<EOF

[JUDGE DEMO READY]

Local dashboards
  READY  kagent UI       http://localhost:18080
  READY  KPI Dashboard  http://localhost:18082/kpi-dashboard.html
  READY  Cyber Staff Dashboard http://localhost:18083
EOF
if [[ "$ARGOCD_STATUS" == READY ]]; then
  echo "  READY  ArgoCD         https://localhost:18081"
else
  echo "  SKIP   ArgoCD         not installed (rerun with INSTALL_ARGOCD=true)"
fi
cat <<EOF

Azure Portal
EOF
print_portal_links "$TENANT_ID" "$WORKSPACE_ID" \
  'Azure OpenAI' "$AOAI_ID" \
  'Simulation AKS' "$SIM_AKS_ID" \
  'SOC AKS' "$SOC_AKS_ID" \
  'Red AKS' "$RED_AKS_ID" \
  'Red ACR' "$RED_ACR_ID" \
  'Artifact Storage' "$RED_STORAGE_ID"
cat <<EOF

Runtime evidence
  ARM deployments    Succeeded
  AKS clusters       sim/soc/red Succeeded + Running
  Agent              Ready=$AGENT_READY
  RemoteMCPServer    Accepted=$MCP_ACCEPTED
  MCP tools          $MCP_TOOLS
  Hosted AI          Azure OpenAI gpt-4o-mini (interaction + summarization)
  Decision authority deterministic gates + HITL + ground-truth validation

Logs and lifecycle
  Runtime directory  $JUDGE_DEMO_RUNTIME_DIR
  Deploy log         $DEPLOY_LOG
  Bootstrap log      $BOOTSTRAP_LOG
  Stop dashboards    bash scripts/stop-judge-demo.sh
  Azure teardown     bash scripts/destroy-all.sh (plan), then rerun with --execute --subscription $SUBSCRIPTION_ID

Subscription: $SUBSCRIPTION_ID
EOF
print_demo_comparison
