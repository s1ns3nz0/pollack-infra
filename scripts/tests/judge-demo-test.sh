#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/judge-demo.sh
source "$SCRIPT_DIR/../lib/judge-demo.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-}"
  [[ "$expected" == "$actual" ]] || fail "expected '$expected', got '$actual' $message"
}

assert_contains() {
  local value="$1"
  local expected="$2"
  [[ "$value" == *"$expected"* ]] || fail "missing '$expected'"
}

resource_id='/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks'
assert_eq \
  "https://portal.azure.com/#@tenant-id/resource${resource_id}/overview" \
  "$(portal_resource_url tenant-id "$resource_id")"

workspace_id='/subscriptions/sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law'
assert_eq \
  'https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/MainMenuBlade/~/0/id/%2Fsubscriptions%2Fsub%2FresourceGroups%2Frg%2Fproviders%2FMicrosoft.OperationalInsights%2Fworkspaces%2Flaw' \
  "$(sentinel_portal_url tenant-id "$workspace_id")"

comparison="$(print_demo_comparison)"
assert_contains "$comparison" 'Short local demo'
assert_contains "$comparison" 'No hosted model'
assert_contains "$comparison" 'Full Azure demo'
assert_contains "$comparison" 'gpt-4o-mini'
assert_contains "$comparison" 'deterministic gates retain authority'

tmp="$(mktemp -d)"
JUDGE_DEMO_RUNTIME_DIR="$tmp/runtime"
cleanup() {
  if [[ -d "$JUDGE_DEMO_RUNTIME_DIR" ]]; then
    for pid_file in "$JUDGE_DEMO_RUNTIME_DIR"/*.pid; do
      [[ -f "$pid_file" ]] || continue
      pid="$(<"$pid_file")"
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    done
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

start_owned_process sample "$tmp/sample.log" sh -c 'sleep 60'
first_pid="$(<"$JUDGE_DEMO_RUNTIME_DIR/sample.pid")"
kill -0 "$first_pid" 2>/dev/null || fail 'owned process did not start'

start_owned_process sample "$tmp/sample.log" sh -c 'sleep 60'
assert_eq "$first_pid" "$(<"$JUDGE_DEMO_RUNTIME_DIR/sample.pid")" 'when reusing a live process'

printf '999999\n' >"$JUDGE_DEMO_RUNTIME_DIR/stale.pid"
start_owned_process stale "$tmp/stale.log" sh -c 'sleep 60'
stale_replacement="$(<"$JUDGE_DEMO_RUNTIME_DIR/stale.pid")"
[[ "$stale_replacement" != 999999 ]] || fail 'stale PID was not replaced'
kill -0 "$stale_replacement" 2>/dev/null || fail 'stale replacement process did not start'

replacement_ppid="$(ps -o ppid= -p "$stale_replacement" | tr -d ' ')"
assert_eq 1 "$replacement_ppid" 'for a process detached from the launcher session'

stop_owned_process sample
if kill -0 "$first_pid" 2>/dev/null; then
  fail 'owned process survived stop'
fi
[[ ! -e "$JUDGE_DEMO_RUNTIME_DIR/sample.pid" ]] || fail 'PID file survived stop'

curl() { return 1; }
sleep() { :; }
if wait_for_http http://127.0.0.1:9 false 0 >/dev/null 2>&1; then
  fail 'HTTP wait did not time out'
fi

command_log="$tmp/command.log"
JUDGE_DEMO_TEST_MODE=true \
JUDGE_DEMO_COMMAND_LOG="$command_log" \
bash "$SCRIPT_DIR/../deploy-judge-demo.sh"
assert_eq \
  'deploy-all discover build-image bootstrap generate-kpi start-dashboards verify print-summary' \
  "$(paste -sd' ' "$command_log")" \
  'for launcher stage order'

launcher="$(<"$SCRIPT_DIR/../deploy-judge-demo.sh")"
stop_script="$(<"$SCRIPT_DIR/../stop-judge-demo.sh")"
assert_contains "$launcher" 'SOC_REPO='
assert_contains "$launcher" 'INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"'
assert_contains "$launcher" 'uvicorn app.dashboard:app'
assert_contains "$launcher" '--port 18083'
assert_contains "$launcher" 'http://localhost:18083'
assert_contains "$launcher" 'Cyber Staff Dashboard'
assert_contains "$stop_script" 'cyber-staff-dashboard'

echo 'judge demo tests passed'
