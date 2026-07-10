#!/usr/bin/env bash

JUDGE_DEMO_RUNTIME_DIR="${JUDGE_DEMO_RUNTIME_DIR:-/tmp/fried-pollack-judge-demo}"

ensure_runtime_dir() {
  mkdir -p "$JUDGE_DEMO_RUNTIME_DIR"
  chmod 700 "$JUDGE_DEMO_RUNTIME_DIR"
}

pid_is_live() {
  local pid_file="$1"
  local pid
  [[ -f "$pid_file" ]] || return 1
  pid="$(<"$pid_file")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

start_owned_process() {
  local name="${1:?process name is required}"
  local log_file="${2:?log file is required}"
  shift 2
  (( $# > 0 )) || {
    echo "No command supplied for $name" >&2
    return 1
  }

  ensure_runtime_dir
  local pid_file="$JUDGE_DEMO_RUNTIME_DIR/$name.pid"
  if pid_is_live "$pid_file"; then
    echo "Reusing $name (pid $(<"$pid_file"))"
    return 0
  fi
  rm -f "$pid_file"
  : >"$log_file"
  local pid
  pid="$(python - "$log_file" "$@" <<'PY'
import subprocess
import sys

log_path, *command = sys.argv[1:]
with open(log_path, "ab", buffering=0) as log:
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
print(process.pid)
PY
)"
  printf '%s\n' "$pid" >"$pid_file"
  sleep 0.2
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pid_file"
    echo "$name exited during startup; see $log_file" >&2
    return 1
  fi
  echo "Started $name (pid $pid, log $log_file)"
}

stop_owned_process() {
  local name="${1:?process name is required}"
  local pid_file="$JUDGE_DEMO_RUNTIME_DIR/$name.pid"
  local pid
  [[ -f "$pid_file" ]] || return 0
  pid="$(<"$pid_file")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

wait_for_http() {
  local url="${1:?URL is required}"
  local allow_insecure="${2:-false}"
  local timeout_seconds="${3:-30}"
  local started_at="$SECONDS"
  local -a curl_args=(-fsS --max-time 2)
  [[ "$allow_insecure" == true ]] && curl_args+=(-k)

  while true; do
    if curl "${curl_args[@]}" "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( SECONDS - started_at >= timeout_seconds )); then
      echo "Timed out waiting for $url" >&2
      return 1
    fi
    sleep 1
  done
}

portal_resource_url() {
  local tenant_id="${1:?tenant ID is required}"
  local resource_id="${2:?resource ID is required}"
  printf 'https://portal.azure.com/#@%s/resource%s/overview\n' "$tenant_id" "$resource_id"
}

sentinel_portal_url() {
  local tenant_id="${1:?tenant ID is required}"
  local workspace_id="${2:?workspace resource ID is required}"
  local encoded_id="${workspace_id//\//%2F}"
  : "$tenant_id"
  printf 'https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/MainMenuBlade/~/0/id/%s\n' "$encoded_id"
}

print_portal_links() {
  local tenant_id="${1:?tenant ID is required}"
  local workspace_id="${2:?workspace resource ID is required}"
  shift 2
  (( $# % 2 == 0 )) || {
    echo "Portal links require label/resource-ID pairs" >&2
    return 1
  }

  printf '  %-18s %s\n' 'Microsoft Sentinel' "$(sentinel_portal_url "$tenant_id" "$workspace_id")"
  printf '  %-18s %s\n' 'Log Analytics' "$(portal_resource_url "$tenant_id" "$workspace_id")"
  while (( $# > 0 )); do
    printf '  %-18s %s\n' "$1" "$(portal_resource_url "$tenant_id" "$2")"
    shift 2
  done
}

print_demo_comparison() {
  cat <<'EOF'
Reviewer paths
  Short local demo : No hosted model; deterministic graph and in-memory range; no Azure cost.
  Full Azure demo  : kagent uses Azure OpenAI gpt-4o-mini for interaction and summarization.
  Authority        : deterministic gates retain authority in both paths; the model cannot approve or execute attacks.
EOF
}
