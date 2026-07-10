#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/judge-demo.sh
source "$SCRIPT_DIR/lib/judge-demo.sh"

for process_name in kagent-ui argocd kpi-dashboard cyber-staff-dashboard; do
  stop_owned_process "$process_name"
done

echo "Judge demo local dashboards stopped. Azure resources were not deleted."
