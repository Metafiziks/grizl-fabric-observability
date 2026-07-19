#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

info "Checking shell syntax"
for script in "${FABRIC_DIR}"/scripts/*.sh; do
  bash -n "${script}"
done
ok "Shell syntax passed"

info "Checking JSON manifests"
for json_file in "${FABRIC_DIR}"/package.json "${FABRIC_DIR}"/manifests/*.json; do
  node -e "const fs = require('fs'); JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));" "${json_file}"
done
ok "JSON manifests parsed"

info "Checking referenced KQL source files"
for kql_file in \
  "${REPO_ROOT}/kql/grizl-observability.kql" \
  "${REPO_ROOT}/kql/grizl-dashboard-tiles.kql" \
  "${REPO_ROOT}/kql/grizl-activator-alerts.kql" \
  "${REPO_ROOT}/kql/grizl-anomaly-signals.kql"; do
  [ -f "${kql_file}" ] || die "Missing KQL source file: ${kql_file}"
done
ok "KQL source files exist"

info "Checking for committed Event Hubs secret material"
if find "${FABRIC_DIR}" -type f ! -path "${FABRIC_DIR}/scripts/check.sh" -print0 |
  xargs -0 grep -E 'Endpoint=sb://|SharedAccessKey=' >/dev/null 2>&1; then
  die "Potential Event Hubs connection string material found under fabric/"
fi
ok "No Event Hubs connection string material detected"

ok "Fabric package local checks passed"
