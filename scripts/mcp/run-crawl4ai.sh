#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
mcp_env_prepare CRAWL4AI_API_TOKEN
: "${CRAWL4AI_API_TOKEN:?Missing CRAWL4AI_API_TOKEN}"
export CRAWL4AI_AUTHORIZATION="Bearer ${CRAWL4AI_API_TOKEN}"
mcp_env_exec_remote http://127.0.0.1:11235/mcp/sse --host 127.0.0.1 --allow-http \
    --transport sse-only --header "Authorization:${CRAWL4AI_AUTHORIZATION}" \
    2> >(sed -E 's/(Authorization":"Bearer )[^"]+/\1<redacted>/g; s/(Authorization:Bearer )[^[:space:]]+/\1<redacted>/g' >&2)
