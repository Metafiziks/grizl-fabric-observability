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

PAYLOAD_FILE="${FABRIC_DATA_AGENT_PAYLOAD:-}"
temp_payload=""
trap 'rm -f "${temp_payload:-}"' EXIT

if [ -n "${PAYLOAD_FILE}" ]; then
  case "${PAYLOAD_FILE}" in
    /*) ;;
    *) PAYLOAD_FILE="${REPO_ROOT}/${PAYLOAD_FILE}" ;;
  esac
  [ -f "${PAYLOAD_FILE}" ] || die "Data Agent payload file not found: ${PAYLOAD_FILE}"
fi

if [ -z "${PAYLOAD_FILE}" ] || grep -q 'TODO_REPLACE' "${PAYLOAD_FILE}"; then
  if [ -n "${PAYLOAD_FILE}" ]; then
    warn "Data Agent payload contains TODO_REPLACE; using shell create payload instead."
  fi
  require_env FABRIC_DATA_AGENT_NAME
  temp_payload="$(mktemp)"
  write_json_payload "${temp_payload}" '({ displayName: process.env.FABRIC_DATA_AGENT_NAME, description: process.env.FABRIC_DATA_AGENT_DESCRIPTION || "GRIZL incident evidence assistant over Fabric Eventhouse/KQL observability data." })'
  PAYLOAD_FILE="${temp_payload}"
fi

warn "Fabric Data Agent creation requires Contributor access, Item.ReadWrite.All, tenant support, and paid supported Fabric capacity (F2+ or compatible Premium)."
ensure_mutation_allowed

info "Creating Fabric Data Agent in workspace ${FABRIC_WORKSPACE_ID}"
run_fab_api post "/v1/workspaces/${FABRIC_WORKSPACE_ID}/dataAgents" "${PAYLOAD_FILE}"

ok "Data Agent create request submitted. After publishing, MCP endpoint format is:"
printf 'https://api.fabric.microsoft.com/v1/mcp/workspaces/%s/dataagents/{DataAgentId}/agent\n' "${FABRIC_WORKSPACE_ID}"
