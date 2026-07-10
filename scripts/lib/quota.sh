#!/usr/bin/env bash

vm_size_vcpus() {
  case "${1:-}" in
    Standard_D2s_v5) printf '2\n' ;;
    Standard_D4s_v5) printf '4\n' ;;
    *)
      echo "Unsupported VM size for quota calculation: ${1:-<empty>}" >&2
      return 1
      ;;
  esac
}

topology_vcpus() {
  if (( $# != 8 )); then
    echo "topology_vcpus requires four VM-size/node-count pairs" >&2
    return 1
  fi

  local total=0
  local size count vcpus
  while (( $# > 0 )); do
    size="$1"
    count="$2"
    shift 2

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
      echo "Node count must be a non-negative integer: $count" >&2
      return 1
    fi
    vcpus="$(vm_size_vcpus "$size")" || return 1
    total=$((total + vcpus * count))
  done

  printf '%s\n' "$total"
}

wait_for_regional_vcpu_capacity() {
  if (( $# != 4 )); then
    echo "wait_for_regional_vcpu_capacity requires location, required free vCPUs, timeout, and poll interval" >&2
    return 1
  fi

  local location="$1"
  local required_free="$2"
  local timeout_seconds="$3"
  local poll_seconds="$4"
  local started_at="$SECONDS"
  local usage limit free

  while true; do
    read -r usage limit <<<"$(
      az vm list-usage --location "$location" \
        --query "[?name.value=='cores'] | [0].{usage:currentValue,limit:limit}" -o tsv
    )"

    if [[ ! "$usage" =~ ^[0-9]+$ || ! "$limit" =~ ^[0-9]+$ ]]; then
      echo "Unable to read regional vCPU usage for $location" >&2
      return 1
    fi

    free=$((limit - usage))
    if (( free >= required_free )); then
      echo "Regional vCPU capacity ready: usage=$usage limit=$limit free=$free required=$required_free"
      return 0
    fi

    if (( SECONDS - started_at >= timeout_seconds )); then
      echo "Timed out waiting for regional vCPU capacity: usage=$usage limit=$limit free=$free required=$required_free" >&2
      return 1
    fi

    echo "Waiting for regional vCPU capacity: usage=$usage limit=$limit free=$free required=$required_free"
    sleep "$poll_seconds"
  done
}
