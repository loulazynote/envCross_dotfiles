#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
bws_guard "$@"
mcp_env_write_cache_from_env
printf 'Wrote %s\n' "$MCP_ENV_CACHE"
