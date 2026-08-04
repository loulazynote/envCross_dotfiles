#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
if [[ -z "${BWS_SECRETS_INJECTED:-}" ]]; then
    mcp_env_sync >/dev/null
    exec "$(mcp_env_root)/scripts/secrets/run.sh" -- "$0" "$@"
fi
mcp_env_write_cache_from_env
exec "$(command -v codex)" --profile linux "$@"
