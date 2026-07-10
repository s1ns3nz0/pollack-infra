#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/quota.sh
source "$SCRIPT_DIR/../lib/quota.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-}"

  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: expected '$expected', got '$actual' $message" >&2
    exit 1
  fi
}

assert_eq 2 "$(vm_size_vcpus Standard_D2s_v5)" "for D2s_v5"
assert_eq 4 "$(vm_size_vcpus Standard_D4s_v5)" "for D4s_v5"
assert_eq 20 "$(
  topology_vcpus \
    Standard_D4s_v5 3 \
    Standard_D4s_v5 1 \
    Standard_D2s_v5 1 \
    Standard_D2s_v5 1
)" "for the lab topology"

if vm_size_vcpus Standard_Unknown >/dev/null 2>&1; then
  echo "FAIL: unknown VM size was accepted" >&2
  exit 1
fi

if topology_vcpus Standard_D4s_v5 nope Standard_D4s_v5 1 Standard_D2s_v5 1 Standard_D2s_v5 1 >/dev/null 2>&1; then
  echo "FAIL: non-integer node count was accepted" >&2
  exit 1
fi

usage_counter="$(mktemp)"
trap 'rm -f "$usage_counter"' EXIT
printf '0\n' >"$usage_counter"
az() {
  local call
  local args="$*"
  call="$(<"$usage_counter")"
  call=$((call + 1))
  printf '%s\n' "$call" >"$usage_counter"
  if [[ "$args" != *"{usage:currentValue,limit:limit}"* ]]; then
    printf '20\n20\n'
    return
  fi
  if (( call == 1 )); then
    printf '20\t20\n'
  else
    printf '16\t20\n'
  fi
}

sleep() { :; }

wait_for_regional_vcpu_capacity koreacentral 4 2 0
assert_eq 2 "$(<"$usage_counter")" "while waiting for released quota"

az() { printf '20\t20\n'; }
if wait_for_regional_vcpu_capacity koreacentral 4 0 0 >/dev/null 2>&1; then
  echo "FAIL: quota wait did not time out" >&2
  exit 1
fi

echo "quota tests passed"
