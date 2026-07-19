#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage: bash fabric/scripts/import-eventstream-definition.sh [options]

Imports an exported Eventstream getDefinition payload into FABRIC_EVENTSTREAM_ID
after remapping Eventhouse destination workspace/item IDs.

Required:
  FABRIC_WORKSPACE_ID
  FABRIC_EVENTSTREAM_ID
  FABRIC_KQL_DATABASE_ID
  FABRIC_EVENTSTREAM_DEFINITION_FILE

Optional:
  FABRIC_KQL_RAW_TABLE_NAME
  FABRIC_EVENTSTREAM_DESTINATION_CONNECTION_NAME
  FABRIC_EVENTSTREAM_DESTINATION_MAPPING_RULE_NAME

USAGE
  usage_common
}

DEFINITION_FILE="${FABRIC_EVENTSTREAM_DEFINITION_FILE:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      [ "$#" -ge 2 ] || die "--config requires a path"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --definition)
      [ "$#" -ge 2 ] || die "--definition requires a path"
      DEFINITION_FILE="$2"
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

if [ -z "${FABRIC_EVENTSTREAM_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_EVENTSTREAM_ID="{FABRIC_EVENTSTREAM_ID}"
else
  require_env FABRIC_EVENTSTREAM_ID
fi

if [ -z "${FABRIC_KQL_DATABASE_ID:-}" ] && [ "${DRY_RUN}" = "true" ]; then
  FABRIC_KQL_DATABASE_ID="{FABRIC_KQL_DATABASE_ID}"
else
  require_env FABRIC_KQL_DATABASE_ID
fi

DEFINITION_FILE="${DEFINITION_FILE:-${FABRIC_EVENTSTREAM_DEFINITION_FILE:-}}"
[ -n "${DEFINITION_FILE}" ] || die "FABRIC_EVENTSTREAM_DEFINITION_FILE or --definition must be set"
case "${DEFINITION_FILE}" in
  /*) ;;
  *) DEFINITION_FILE="${REPO_ROOT}/${DEFINITION_FILE}" ;;
esac
[ -f "${DEFINITION_FILE}" ] || die "Eventstream definition file not found: ${DEFINITION_FILE}"

remapped_payload="$(mktemp)"
trap 'rm -f "${remapped_payload:-}"' EXIT

node - "${DEFINITION_FILE}" "${remapped_payload}" <<'NODE'
const fs = require('fs');

const [inputPath, outputPath] = process.argv.slice(2);
const raw = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const source = raw.definition ? raw : (raw.text?.definition ? raw.text : null);
if (!source?.definition?.parts) {
  throw new Error('Expected a Fabric getDefinition payload with definition.parts');
}

const targetWorkspaceId = process.env.FABRIC_WORKSPACE_ID;
const targetKqlDatabaseId = process.env.FABRIC_KQL_DATABASE_ID;
const targetTableName = process.env.FABRIC_KQL_RAW_TABLE_NAME || 'RawLogs';
const connectionName = process.env.FABRIC_EVENTSTREAM_DESTINATION_CONNECTION_NAME || '';
const mappingRuleName = process.env.FABRIC_EVENTSTREAM_DESTINATION_MAPPING_RULE_NAME || '';

const output = JSON.parse(JSON.stringify(source));
const eventstreamPart = output.definition.parts.find((part) => part.path === 'eventstream.json');
if (!eventstreamPart?.payload) {
  throw new Error('Expected an eventstream.json InlineBase64 part');
}

const eventstream = JSON.parse(Buffer.from(eventstreamPart.payload, 'base64').toString('utf8'));
const destinations = Array.isArray(eventstream.destinations) ? eventstream.destinations : [];
let remappedCount = 0;

for (const destination of destinations) {
  const properties = destination.properties || destination.config || {};
  const isEventhouse =
    destination.type === 'Eventhouse' ||
    destination.destinationType === 'Eventhouse' ||
    properties.type === 'Eventhouse' ||
    Object.prototype.hasOwnProperty.call(properties, 'tableName');

  if (!isEventhouse) {
    continue;
  }

  destination.properties = properties;
  properties.workspaceId = targetWorkspaceId;
  properties.itemId = targetKqlDatabaseId;
  properties.tableName = targetTableName;
  if (connectionName) {
    properties.connectionName = connectionName;
  }
  if (mappingRuleName) {
    properties.mappingRuleName = mappingRuleName;
  }
  remappedCount += 1;
}

eventstreamPart.payload = Buffer.from(JSON.stringify(eventstream, null, 2)).toString('base64');
fs.writeFileSync(outputPath, JSON.stringify(output, null, 2) + '\n');

console.error(`[INFO]  Eventstream definition has ${Array.isArray(eventstream.sources) ? eventstream.sources.length : 0} source(s), ${destinations.length} destination(s), remapped ${remappedCount} Eventhouse destination(s).`);
if (remappedCount === 0) {
  console.error('[WARN]  No Eventhouse destination was remapped. A shell Eventstream export may have empty sources/destinations.');
}
NODE

info "Updating Eventstream definition for item ${FABRIC_EVENTSTREAM_ID}"
run_fab_api post "/v1/workspaces/${FABRIC_WORKSPACE_ID}/items/${FABRIC_EVENTSTREAM_ID}/updateDefinition" "${remapped_payload}"
ok "Eventstream updateDefinition request submitted."
