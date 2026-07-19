#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage: bash fabric/scripts/kusto-mgmt.sh [options]

Executes one Kusto management command against the Fabric Eventhouse KQL
database through <queryServiceUri>/v1/rest/mgmt.

Options:
  --command <csl>  Management command text, for example '.show tables'
  --file <path>    Read management command text from a file

Required config:
  FABRIC_KQL_QUERY_SERVICE_URI
  FABRIC_KQL_DATABASE_NAME

Authentication:
  Uses Azure CLI to request a token for https://api.kusto.windows.net.
  Run 'az login' with a Fabric/Kusto-authorized identity before live use.

USAGE
  usage_common
}

KUSTO_COMMAND=""
KUSTO_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      [ "$#" -ge 2 ] || die "--config requires a path"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --command)
      [ "$#" -ge 2 ] || die "--command requires a value"
      KUSTO_COMMAND="$2"
      shift 2
      ;;
    --file)
      [ "$#" -ge 2 ] || die "--file requires a path"
      KUSTO_FILE="$2"
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

if [ -n "${KUSTO_COMMAND}" ] && [ -n "${KUSTO_FILE}" ]; then
  die "Use either --command or --file, not both"
fi

if [ -z "${KUSTO_COMMAND}" ] && [ -z "${KUSTO_FILE}" ]; then
  die "A management command is required via --command or --file"
fi

if [ -z "${FABRIC_KQL_QUERY_SERVICE_URI:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_KQL_QUERY_SERVICE_URI="https://<cluster>.<region>.kusto.fabric.microsoft.com"
else
  require_env FABRIC_KQL_QUERY_SERVICE_URI
fi

if [ -z "${FABRIC_KQL_DATABASE_NAME:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_KQL_DATABASE_NAME="{FABRIC_KQL_DATABASE_NAME}"
else
  require_env FABRIC_KQL_DATABASE_NAME
fi
ensure_mutation_allowed

if [ -n "${KUSTO_FILE}" ]; then
  case "${KUSTO_FILE}" in
    /*) ;;
    *) KUSTO_FILE="${REPO_ROOT}/${KUSTO_FILE}" ;;
  esac
  [ -f "${KUSTO_FILE}" ] || die "Kusto command file not found: ${KUSTO_FILE}"
  KUSTO_COMMAND="$(cat "${KUSTO_FILE}")"
fi

payload_file="$(mktemp)"
trap 'rm -f "${payload_file:-}"' EXIT
export KUSTO_COMMAND
write_json_payload "${payload_file}" '({ db: process.env.FABRIC_KQL_DATABASE_NAME, csl: process.env.KUSTO_COMMAND })'

endpoint="${FABRIC_KQL_QUERY_SERVICE_URI%/}/v1/rest/mgmt"

if [ "${DRY_RUN}" = "true" ]; then
  quote_cmd curl -sS "${endpoint}" -H "Authorization: Bearer <kusto-token>" -H "Content-Type: application/json" -d "@${payload_file}"
  exit 0
fi

require_cmd az
require_cmd curl

token="$(az account get-access-token \
  --resource https://api.kusto.windows.net \
  --query accessToken \
  --output tsv)"

if [ -z "${token}" ]; then
  die "Azure CLI did not return a Kusto access token"
fi

curl -sS "${endpoint}" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  -d "@${payload_file}"
