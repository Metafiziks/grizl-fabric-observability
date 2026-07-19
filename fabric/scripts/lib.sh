#!/usr/bin/env bash

if [ -n "${GRIZL_FABRIC_LIB_SOURCED:-}" ]; then
  return 0
fi
GRIZL_FABRIC_LIB_SOURCED=1

FABRIC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_DIR="$(cd "${FABRIC_SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FABRIC_DIR}/.." && pwd)"

CONFIG_FILE="${CONFIG_FILE:-${FABRIC_DIR}/config/grizl.fabric.env}"
DRY_RUN="${DRY_RUN:-false}"
YES="${YES:-false}"

info() { printf '[INFO]  %s\n' "$*"; }
ok() { printf '[OK]    %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }
die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage_common() {
  cat <<'USAGE'
Common options:
  --config <path>  Load env vars from a config file (default: fabric/config/grizl.fabric.env)
  --dry-run        Print Fabric API calls without executing them
  --yes            Required for live create/delete operations
USAGE
}

parse_common_args() {
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
      *)
        return 0
        ;;
    esac
  done
}

load_env_file() {
  if [ -f "${CONFIG_FILE}" ]; then
    info "Loading config ${CONFIG_FILE}"
    set -a
    # shellcheck source=/dev/null
    . "${CONFIG_FILE}"
    set +a
  else
    warn "Config file not found: ${CONFIG_FILE}"
    warn "Copy fabric/config/grizl.fabric.env.example to fabric/config/grizl.fabric.env or pass --config."
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_fab() {
  require_cmd fab
}

require_fab_auth() {
  if [ "${DRY_RUN}" = "true" ]; then
    info "Dry-run mode: skipping Fabric auth check."
    return 0
  fi

  if fab auth status >/dev/null 2>&1; then
    ok "Fabric CLI authentication detected."
    return 0
  fi

  die "Fabric CLI is installed but not authenticated. Run 'fab auth login' for the target tenant, then retry."
}

require_env() {
  local name="$1"
  eval "local value=\${${name}:-}"
  [ -n "${value}" ] || die "${name} must be set"
}

ensure_mutation_allowed() {
  if [ "${DRY_RUN}" = "true" ]; then
    return 0
  fi

  [ "${YES}" = "true" ] || die "Live Fabric mutations require --yes. Re-run with --dry-run first."
}

quote_cmd() {
  local first=true
  for arg in "$@"; do
    if [ "${first}" = "true" ]; then
      first=false
    else
      printf ' '
    fi
    printf '%q' "${arg}"
  done
  printf '\n'
}

run_fab_api() {
  local method="$1"
  local endpoint="$2"
  local body_file="${3:-}"
  local normalized_endpoint="${endpoint}"
  local normalized_method

  normalized_endpoint="${normalized_endpoint#/v1/}"
  normalized_endpoint="${normalized_endpoint#/}"
  normalized_method="$(printf '%s' "${method}" | tr '[:upper:]' '[:lower:]')"

  local cmd=(fab api "${normalized_endpoint}" -X "${normalized_method}")

  if [ -n "${body_file}" ]; then
    cmd+=(-i "${body_file}")
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    quote_cmd "${cmd[@]}"
    return 0
  fi

  "${cmd[@]}"
}

write_json_payload() {
  local output_file="$1"
  local js_expression="$2"
  require_cmd node
  node -e "const fs = require('fs'); const payload = ${js_expression}; fs.writeFileSync(process.argv[1], JSON.stringify(payload, null, 2) + '\n');" "${output_file}"
}
