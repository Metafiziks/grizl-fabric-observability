#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

parse_common_args "$@"
load_env_file

if [ "${DRY_RUN}" != "true" ]; then
  require_fab
fi
require_fab_auth
if [ -z "${FABRIC_WORKSPACE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_WORKSPACE_ID="{FABRIC_WORKSPACE_ID}"
else
  require_env FABRIC_WORKSPACE_ID
fi
ensure_mutation_allowed

delete_item_if_set() {
  local label="$1"
  local item_id="$2"

  if [ -z "${item_id}" ]; then
    warn "Skipping ${label}: item ID not set."
    return 0
  fi

  info "Deleting ${label} item ${item_id}"
  run_fab_api delete "/v1/workspaces/${FABRIC_WORKSPACE_ID}/items/${item_id}"
}

delete_item_if_set "Data Agent" "${FABRIC_DATA_AGENT_ID:-}"
delete_item_if_set "Reflex/Activator" "${FABRIC_REFLEX_ID:-}"
delete_item_if_set "KQL Dashboard" "${FABRIC_DASHBOARD_ID:-}"
delete_item_if_set "Eventstream" "${FABRIC_EVENTSTREAM_ID:-}"
delete_item_if_set "KQL Database" "${FABRIC_KQL_DATABASE_ID:-}"
delete_item_if_set "Eventhouse" "${FABRIC_EVENTHOUSE_ID:-}"

if [ "${FABRIC_DELETE_WORKSPACE:-false}" = "true" ]; then
  info "Deleting workspace ${FABRIC_WORKSPACE_ID}"
  run_fab_api delete "/v1/workspaces/${FABRIC_WORKSPACE_ID}"
else
  warn "Workspace deletion skipped. Set FABRIC_DELETE_WORKSPACE=true to delete the workspace itself."
fi

ok "Teardown script finished."
