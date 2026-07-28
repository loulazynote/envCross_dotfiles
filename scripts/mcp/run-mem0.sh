#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
if [[ -z "${MEM0_API_KEY:-}" && -z "${MEM0_AUTHORIZATION:-}" ]]; then
    mcp_env_prepare MEM0_API_KEY || mcp_env_prepare MEM0_AUTHORIZATION || true
    mcp_env_load_cache || true
fi
if [[ -z "${MEM0_AUTHORIZATION:-}" && -n "${MEM0_API_KEY:-}" ]]; then
    export MEM0_AUTHORIZATION="Bearer ${MEM0_API_KEY}"
elif [[ "${MEM0_AUTHORIZATION:-}" == Token\ * ]]; then
    export MEM0_AUTHORIZATION="Bearer ${MEM0_AUTHORIZATION#Token }"
fi
: "${MEM0_AUTHORIZATION:?Missing MEM0_API_KEY or MEM0_AUTHORIZATION}"
mcp_env_exec_remote "https://mcp.mem0.ai/mcp/" --host 127.0.0.1 \
    --header "Authorization:${MEM0_AUTHORIZATION}" \
    2> >(sed -E 's/(Authorization":"Bearer )[^"]+/\1<redacted>/g; s/(Authorization:Bearer )[^[:space:]]+/\1<redacted>/g' >&2)
