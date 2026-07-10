#!/usr/bin/env bash

recover_deleted_aoai_accounts() {
  local resource_group="$1"
  local location="$2"
  local deleted_names

  deleted_names="$(
    az cognitiveservices account list-deleted \
      --query "[?kind=='OpenAI' && location=='${location}' && contains(id, '/resourceGroups/${resource_group}/deletedAccounts/')].name" \
      -o tsv
  )"

  if [[ -z "$deleted_names" ]]; then
    return
  fi

  while IFS= read -r account_name; do
    [[ -n "$account_name" ]] || continue
    echo "Recovering soft-deleted Azure OpenAI account: $account_name"
    az cognitiveservices account recover \
      --location "$location" \
      --resource-group "$resource_group" \
      --name "$account_name" \
      -o none
  done <<<"$deleted_names"
}
