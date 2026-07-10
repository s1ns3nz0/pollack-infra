#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZ_BIN="${AZ_BIN:-az}"
STOP_SCRIPT="${STOP_SCRIPT:-$SCRIPT_DIR/stop-judge-demo.sh}"
DELETE_TIMEOUT="${DELETE_TIMEOUT:-3600}"
DELETE_POLL_SECONDS="${DELETE_POLL_SECONDS:-10}"
EXECUTE=false
EXPECTED_SUBSCRIPTION=''

usage() {
  cat <<'EOF'
Usage:
  bash scripts/destroy-all.sh
  bash scripts/destroy-all.sh --execute --subscription <subscription-id>

Without --execute, prints the exact deletion plan and changes nothing.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --execute)
      EXECUTE=true
      shift
      ;;
    --subscription)
      [[ $# -ge 2 ]] || { echo '--subscription requires a value' >&2; exit 2; }
      EXPECTED_SUBSCRIPTION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ACTIVE_SUBSCRIPTION="$("$AZ_BIN" account show --query id -o tsv)"
FIXED_GROUPS=(dah-data-rg dah-soc-rg dah-sim-rg dah-red-rg)
declare -a NODE_GROUPS=()

discover_node_group() {
  local resource_group="$1"
  local cluster_name="$2"
  local node_group
  node_group="$(
    "$AZ_BIN" aks show -g "$resource_group" -n "$cluster_name" \
      --query nodeResourceGroup -o tsv 2>/dev/null || true
  )"
  if [[ -n "$node_group" ]]; then
    NODE_GROUPS+=("$node_group")
  fi
}

discover_node_group dah-sim-rg dah-sim-aks
discover_node_group dah-soc-rg dah-soc-aks
discover_node_group dah-red-rg dah-red-aks
TARGET_GROUPS=("${FIXED_GROUPS[@]}" "${NODE_GROUPS[@]}")

echo "Active subscription: $ACTIVE_SUBSCRIPTION"
echo 'Authorized deletion targets:'
for resource_group in "${TARGET_GROUPS[@]}"; do
  echo "  - $resource_group"
done

if [[ "$EXECUTE" != true ]]; then
  echo
  echo 'PLAN ONLY: no Azure resources were deleted.'
  echo "Execute with: bash scripts/destroy-all.sh --execute --subscription $ACTIVE_SUBSCRIPTION"
  exit 0
fi

[[ -n "$EXPECTED_SUBSCRIPTION" ]] || {
  echo '--execute requires --subscription <active-subscription-id>' >&2
  exit 2
}
[[ "$EXPECTED_SUBSCRIPTION" == "$ACTIVE_SUBSCRIPTION" ]] || {
  echo "Subscription mismatch: active=$ACTIVE_SUBSCRIPTION supplied=$EXPECTED_SUBSCRIPTION" >&2
  exit 2
}

if [[ -x "$STOP_SCRIPT" ]]; then
  "$STOP_SCRIPT"
else
  bash "$STOP_SCRIPT"
fi

declare -a SUBMITTED_GROUPS=()
for resource_group in "${TARGET_GROUPS[@]}"; do
  if [[ "$("$AZ_BIN" group exists --name "$resource_group" -o tsv)" == true ]]; then
    echo "Submitting deletion: $resource_group"
    "$AZ_BIN" group delete --name "$resource_group" --yes --no-wait
    SUBMITTED_GROUPS+=("$resource_group")
  else
    echo "Already absent: $resource_group"
  fi
done

started_at="$SECONDS"
while true; do
  remaining=()
  for resource_group in "${TARGET_GROUPS[@]}"; do
    if [[ "$("$AZ_BIN" group exists --name "$resource_group" -o tsv)" == true ]]; then
      remaining+=("$resource_group")
    fi
  done
  if (( ${#remaining[@]} == 0 )); then
    break
  fi
  if (( SECONDS - started_at >= DELETE_TIMEOUT )); then
    echo "Timed out waiting for deletion: ${remaining[*]}" >&2
    exit 1
  fi
  echo "Waiting for deletion: ${remaining[*]}"
  sleep "$DELETE_POLL_SECONDS"
done

echo
echo 'TEARDOWN COMPLETE'
for resource_group in "${TARGET_GROUPS[@]}"; do
  echo "  ABSENT  $resource_group"
done
