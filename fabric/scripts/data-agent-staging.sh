#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage: bash fabric/scripts/data-agent-staging.sh <action> [options]

Actions:
  settings-get       GET staging/settings
  settings-patch     PATCH staging/settings using --body <json>
  datasource-add     POST staging/datasources using --body <json>, or generate a KQLDatabase FabricItem body from config
  datasources-get    GET staging/datasources
  elements-get       GET staging datasource elements; accepts --datasource-id, --root-id, --element-id
  elements-patch     PATCH staging datasource elements using --body <json>
  fewshots-get       GET staging datasource fewshots; accepts --datasource-id
  fewshots-post      POST staging datasource fewshots using --body <json>
  publish            POST staging/publish

Common ids come from fabric/config/grizl.fabric.env:
  FABRIC_WORKSPACE_ID, FABRIC_DATA_AGENT_ID, FABRIC_KQL_DATABASE_ID,
  FABRIC_DATA_AGENT_DATASOURCE_ID, FABRIC_DATA_AGENT_ROOT_ID,
  FABRIC_DATA_AGENT_ELEMENT_ID

USAGE
  usage_common
}

[ "$#" -gt 0 ] || { usage; exit 1; }
ACTION="$1"
shift

BODY_FILE=""
DATASOURCE_ID="${FABRIC_DATA_AGENT_DATASOURCE_ID:-}"
ROOT_ID="${FABRIC_DATA_AGENT_ROOT_ID:-}"
ELEMENT_ID="${FABRIC_DATA_AGENT_ELEMENT_ID:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      [ "$#" -ge 2 ] || die "--config requires a path"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --body)
      [ "$#" -ge 2 ] || die "--body requires a path"
      BODY_FILE="$2"
      shift 2
      ;;
    --datasource-id)
      [ "$#" -ge 2 ] || die "--datasource-id requires a value"
      DATASOURCE_ID="$2"
      shift 2
      ;;
    --root-id)
      [ "$#" -ge 2 ] || die "--root-id requires a value"
      ROOT_ID="$2"
      shift 2
      ;;
    --element-id)
      [ "$#" -ge 2 ] || die "--element-id requires a value"
      ELEMENT_ID="$2"
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

load_env_file
DATASOURCE_ID="${DATASOURCE_ID:-${FABRIC_DATA_AGENT_DATASOURCE_ID:-}}"
ROOT_ID="${ROOT_ID:-${FABRIC_DATA_AGENT_ROOT_ID:-}}"
ELEMENT_ID="${ELEMENT_ID:-${FABRIC_DATA_AGENT_ELEMENT_ID:-}}"
if [ "${DRY_RUN}" != "true" ]; then
  require_fab
fi
require_fab_auth
ensure_mutation_allowed

if [ -z "${FABRIC_WORKSPACE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_WORKSPACE_ID="{FABRIC_WORKSPACE_ID}"
else
  require_env FABRIC_WORKSPACE_ID
fi

if [ -z "${FABRIC_DATA_AGENT_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_DATA_AGENT_ID="{FABRIC_DATA_AGENT_ID}"
else
  require_env FABRIC_DATA_AGENT_ID
fi

resolve_body_file() {
  if [ -z "${BODY_FILE}" ]; then
    die "$1 requires --body <json>"
  fi
  case "${BODY_FILE}" in
    /*) ;;
    *) BODY_FILE="${REPO_ROOT}/${BODY_FILE}" ;;
  esac
  [ -f "${BODY_FILE}" ] || die "Body file not found: ${BODY_FILE}"
}

agent_endpoint="/v1/workspaces/${FABRIC_WORKSPACE_ID}/dataAgents/${FABRIC_DATA_AGENT_ID}/staging"

case "${ACTION}" in
  settings-get)
    run_fab_api get "${agent_endpoint}/settings"
    ;;
  settings-patch)
    resolve_body_file "${ACTION}"
    run_fab_api patch "${agent_endpoint}/settings" "${BODY_FILE}"
    ;;
  datasource-add)
    temp_body=""
    trap 'rm -f "${temp_body:-}"' EXIT
    if [ -z "${BODY_FILE}" ]; then
      if [ -z "${FABRIC_KQL_DATABASE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
        FABRIC_KQL_DATABASE_ID="{FABRIC_KQL_DATABASE_ID}"
      else
        require_env FABRIC_KQL_DATABASE_ID
      fi
      temp_body="$(mktemp)"
      write_json_payload "${temp_body}" '({ type: "FabricItem", itemReference: { referenceType: "ById", itemId: process.env.FABRIC_KQL_DATABASE_ID, workspaceId: process.env.FABRIC_WORKSPACE_ID } })'
      BODY_FILE="${temp_body}"
    else
      resolve_body_file "${ACTION}"
    fi
    run_fab_api post "${agent_endpoint}/datasources" "${BODY_FILE}"
    ;;
  datasources-get)
    run_fab_api get "${agent_endpoint}/datasources"
    ;;
  elements-get)
    [ -n "${DATASOURCE_ID}" ] || DATASOURCE_ID="{DATASOURCE_ID}"
    endpoint="${agent_endpoint}/datasources/${DATASOURCE_ID}/elements"
    query=""
    [ -n "${ROOT_ID}" ] && query="${query}${query:+&}rootId=${ROOT_ID}"
    [ -n "${ELEMENT_ID}" ] && query="${query}${query:+&}id=${ELEMENT_ID}"
    [ -n "${query}" ] && endpoint="${endpoint}?${query}"
    run_fab_api get "${endpoint}"
    ;;
  elements-patch)
    resolve_body_file "${ACTION}"
    [ -n "${DATASOURCE_ID}" ] || DATASOURCE_ID="{DATASOURCE_ID}"
    endpoint="${agent_endpoint}/datasources/${DATASOURCE_ID}/elements"
    query=""
    [ -n "${ROOT_ID}" ] && query="${query}${query:+&}rootId=${ROOT_ID}"
    [ -n "${ELEMENT_ID}" ] && query="${query}${query:+&}id=${ELEMENT_ID}"
    [ -n "${query}" ] && endpoint="${endpoint}?${query}"
    run_fab_api patch "${endpoint}" "${BODY_FILE}"
    ;;
  fewshots-get)
    [ -n "${DATASOURCE_ID}" ] || DATASOURCE_ID="{DATASOURCE_ID}"
    run_fab_api get "${agent_endpoint}/datasources/${DATASOURCE_ID}/fewshots"
    ;;
  fewshots-post)
    resolve_body_file "${ACTION}"
    [ -n "${DATASOURCE_ID}" ] || DATASOURCE_ID="{DATASOURCE_ID}"
    run_fab_api post "${agent_endpoint}/datasources/${DATASOURCE_ID}/fewshots" "${BODY_FILE}"
    ;;
  publish)
    run_fab_api post "${agent_endpoint}/publish"
    ;;
  *)
    die "Unknown action: ${ACTION}"
    ;;
esac
