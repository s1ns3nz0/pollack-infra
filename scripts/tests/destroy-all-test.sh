#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
calls="$tmp/calls.log"
state="$tmp/state"
mkdir -p "$state"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "missing '$2'"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "unexpected '$2'"
}

stub_az="$tmp/az"
cat >"$stub_az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$AZ_CALLS"

if [[ "$1 $2" == 'account show' ]]; then
  echo 'sub-good'
  exit 0
fi

if [[ "$1 $2" == 'aks show' ]]; then
  rg=''
  while (( $# > 0 )); do
    if [[ "$1" == -g ]]; then rg="$2"; break; fi
    shift
  done
  case "$rg" in
    dah-sim-rg) echo 'dah-sim-rg-aks-nodes' ;;
    dah-soc-rg) echo 'dah-soc-rg-aks-nodes' ;;
    dah-red-rg) echo 'dah-red-rg-aks-nodes' ;;
    *) exit 3 ;;
  esac
  exit 0
fi

if [[ "$1 $2" == 'group exists' ]]; then
  name=''
  while (( $# > 0 )); do
    if [[ "$1" == --name || "$1" == -n ]]; then name="$2"; break; fi
    shift
  done
  [[ -f "$AZ_STATE/$name" ]] && echo true || echo false
  exit 0
fi

if [[ "$1 $2" == 'group delete' ]]; then
  name=''
  while (( $# > 0 )); do
    if [[ "$1" == --name || "$1" == -n ]]; then name="$2"; break; fi
    shift
  done
  rm -f "$AZ_STATE/$name"
  exit 0
fi

echo "unsupported stub call: $*" >&2
exit 4
EOF
chmod +x "$stub_az"

stop_stub="$tmp/stop"
cat >"$stop_stub" <<'EOF'
#!/usr/bin/env bash
echo stop >>"$AZ_CALLS"
EOF
chmod +x "$stop_stub"

for rg in \
  dah-data-rg dah-soc-rg dah-sim-rg dah-red-rg \
  dah-sim-rg-aks-nodes dah-soc-rg-aks-nodes dah-red-rg-aks-nodes \
  dah-unrelated-rg; do
  touch "$state/$rg"
done

export AZ_BIN="$stub_az" AZ_CALLS="$calls" AZ_STATE="$state" STOP_SCRIPT="$stop_stub"

plan_output="$(bash "$SCRIPT_DIR/../destroy-all.sh")"
assert_contains "$plan_output" 'PLAN ONLY'
for rg in dah-data-rg dah-soc-rg dah-sim-rg dah-red-rg; do
  assert_contains "$plan_output" "$rg"
done
assert_not_contains "$(<"$calls")" 'group delete'
assert_not_contains "$plan_output" 'dah-unrelated-rg'

if bash "$SCRIPT_DIR/../destroy-all.sh" --execute --subscription sub-wrong >/dev/null 2>&1; then
  fail 'subscription mismatch was accepted'
fi

: >"$calls"
execute_output="$(bash "$SCRIPT_DIR/../destroy-all.sh" --execute --subscription sub-good)"
assert_contains "$execute_output" 'TEARDOWN COMPLETE'
for rg in \
  dah-data-rg dah-soc-rg dah-sim-rg dah-red-rg \
  dah-sim-rg-aks-nodes dah-soc-rg-aks-nodes dah-red-rg-aks-nodes; do
  [[ ! -f "$state/$rg" ]] || fail "$rg survived deletion"
done
[[ -f "$state/dah-unrelated-rg" ]] || fail 'unrelated group was deleted'
assert_contains "$(<"$calls")" 'group delete'

echo 'destroy-all tests passed'
