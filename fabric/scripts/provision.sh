#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage: bash fabric/scripts/provision.sh [options] [targets]

Targets:
  --all           Provision all currently automatable resources
  --workspace     Create the Fabric workspace with the configured display name
  --eventhouse    Create the Eventhouse in an existing workspace
  --kql-database  Create the KQL database in an existing workspace
  --eventstream   Create the Eventstream shell in an existing workspace
  --data-agent    Create a Data Agent from FABRIC_DATA_AGENT_PAYLOAD

This script intentionally does not fake Eventstream custom source routing,
dashboard, or Reflex definitions. Export the live tenant definitions first and
replace TODO manifests when Fabric exposes stable import/export for those items.

USAGE
  usage_common
}

RUN_WORKSPACE=false
RUN_EVENTHOUSE=false
RUN_KQL_DATABASE=false
RUN_EVENTSTREAM=false
RUN_DATA_AGENT=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      [ "$#" -ge 2 ] || die "--config requires a path"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      YES=true
      shift
      ;;
    --all)
      RUN_WORKSPACE=true
      RUN_EVENTHOUSE=true
      RUN_KQL_DATABASE=true
      RUN_EVENTSTREAM=true
      shift
      ;;
    --workspace)
      RUN_WORKSPACE=true
      shift
      ;;
    --eventhouse)
      RUN_EVENTHOUSE=true
      shift
      ;;
    --kql-database)
      RUN_KQL_DATABASE=true
      shift
      ;;
    --eventstream)
      RUN_EVENTSTREAM=true
      shift
      ;;
    --data-agent)
      RUN_DATA_AGENT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if [ "${RUN_WORKSPACE}" = "false" ] &&
   [ "${RUN_EVENTHOUSE}" = "false" ] &&
   [ "${RUN_KQL_DATABASE}" = "false" ] &&
   [ "${RUN_EVENTSTREAM}" = "false" ] &&
   [ "${RUN_DATA_AGENT}" = "false" ]; then
  RUN_WORKSPACE=true
  RUN_EVENTHOUSE=true
  RUN_KQL_DATABASE=true
  RUN_EVENTSTREAM=true
fi

load_env_file
if [ "${DRY_RUN}" != "true" ]; then
  require_fab
fi
require_fab_auth
ensure_mutation_allowed

workspace_payload=""
eventhouse_payload=""
kql_payload=""
eventstream_payload=""
trap 'rm -f "${workspace_payload:-}" "${eventhouse_payload:-}" "${kql_payload:-}" "${eventstream_payload:-}"' EXIT

if [ "${RUN_WORKSPACE}" = "true" ]; then
  require_env FABRIC_WORKSPACE_NAME
  workspace_payload="$(mktemp)"
  write_json_payload "${workspace_payload}" '({ displayName: process.env.FABRIC_WORKSPACE_NAME })'
  info "Creating Fabric workspace '${FABRIC_WORKSPACE_NAME}'"
  run_fab_api post "/v1/workspaces" "${workspace_payload}"
  warn "If this created a workspace, capture its ID and set FABRIC_WORKSPACE_ID before creating child items."
fi

if [ "${RUN_EVENTHOUSE}" = "true" ]; then
  if [ -z "${FABRIC_WORKSPACE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
    FABRIC_WORKSPACE_ID="{FABRIC_WORKSPACE_ID}"
  else
    require_env FABRIC_WORKSPACE_ID
  fi
  require_env FABRIC_EVENTHOUSE_NAME
  eventhouse_payload="$(mktemp)"
  write_json_payload "${eventhouse_payload}" '({ displayName: process.env.FABRIC_EVENTHOUSE_NAME })'
  info "Creating Eventhouse '${FABRIC_EVENTHOUSE_NAME}' in workspace ${FABRIC_WORKSPACE_ID}"
  run_fab_api post "/v1/workspaces/${FABRIC_WORKSPACE_ID}/eventhouses" "${eventhouse_payload}"
fi

if [ "${RUN_KQL_DATABASE}" = "true" ]; then
  if [ -z "${FABRIC_WORKSPACE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
    FABRIC_WORKSPACE_ID="{FABRIC_WORKSPACE_ID}"
  else
    require_env FABRIC_WORKSPACE_ID
  fi
  require_env FABRIC_KQL_DATABASE_NAME
  kql_payload="$(mktemp)"
  write_json_payload "${kql_payload}" '({ displayName: process.env.FABRIC_KQL_DATABASE_NAME })'
  info "Creating KQL database '${FABRIC_KQL_DATABASE_NAME}' in workspace ${FABRIC_WORKSPACE_ID}"
  run_fab_api post "/v1/workspaces/${FABRIC_WORKSPACE_ID}/kqlDatabases" "${kql_payload}"
  warn "Apply table/function KQL from kql/grizl-observability.kql after the database exists."
fi

if [ "${RUN_EVENTSTREAM}" = "true" ]; then
  if [ -z "${FABRIC_WORKSPACE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
    FABRIC_WORKSPACE_ID="{FABRIC_WORKSPACE_ID}"
  else
    require_env FABRIC_WORKSPACE_ID
  fi
  require_env FABRIC_EVENTSTREAM_NAME
  eventstream_payload="$(mktemp)"
  write_json_payload "${eventstream_payload}" '({ displayName: process.env.FABRIC_EVENTSTREAM_NAME })'
  info "Creating Eventstream shell '${FABRIC_EVENTSTREAM_NAME}' in workspace ${FABRIC_WORKSPACE_ID}"
  run_fab_api post "/v1/workspaces/${FABRIC_WORKSPACE_ID}/eventstreams" "${eventstream_payload}"
  warn "Custom Event Hubs-compatible source '${FABRIC_EVENTSTREAM_SOURCE_NAME:-GRIZL-Source}' and routing to RawLogs remain export-first/manual until a verified item definition is captured."
fi

if [ "${RUN_DATA_AGENT}" = "true" ]; then
  data_agent_args=(--config "${CONFIG_FILE}")
  if [ "${DRY_RUN}" = "true" ]; then
    data_agent_args+=(--dry-run)
  fi
  if [ "${YES}" = "true" ]; then
    data_agent_args+=(--yes)
  fi
  bash "${SCRIPT_DIR}/create-data-agent.sh" "${data_agent_args[@]}"
fi

ok "Provision script finished."
