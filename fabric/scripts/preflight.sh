#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

parse_common_args "$@"
load_env_file

if [ "${DRY_RUN}" = "true" ]; then
  warn "Dry-run preflight: skipping Fabric CLI presence/auth checks."
else
  require_fab
  require_fab_auth
fi

require_env FABRIC_TENANT_ID
require_env FABRIC_WORKSPACE_NAME
require_env FABRIC_EVENTSTREAM_NAME
require_env FABRIC_EVENTHOUSE_NAME
require_env FABRIC_KQL_DATABASE_NAME

ok "Fabric CLI preflight passed for workspace '${FABRIC_WORKSPACE_NAME}'."
if [ -z "${FABRIC_WORKSPACE_ID:-}" ]; then
  warn "FABRIC_WORKSPACE_ID is not set. Export live item IDs before item-level provision/teardown."
fi
