#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/aoai.sh
source "$SCRIPT_DIR/../lib/aoai.sh"

calls="$(mktemp)"
trap 'rm -f "$calls"' EXIT

az() {
  printf '%s\n' "$*" >>"$calls"
  if [[ "$1 $2 $3" == 'cognitiveservices account list-deleted' ]]; then
    printf 'dah-aoai-target\n'
  fi
}

recover_deleted_aoai_accounts dah-soc-rg koreacentral

grep -Fq "contains(id, '/resourceGroups/dah-soc-rg/deletedAccounts/')" "$calls"
grep -Fq 'cognitiveservices account recover --location koreacentral --resource-group dah-soc-rg --name dah-aoai-target -o none' "$calls"

: >"$calls"
az() {
  printf '%s\n' "$*" >>"$calls"
}
recover_deleted_aoai_accounts dah-soc-rg koreacentral
if grep -Fq 'account recover' "$calls"; then
  echo 'FAIL: recover was called without a matching soft-deleted account' >&2
  exit 1
fi

echo 'aoai recovery tests passed'
