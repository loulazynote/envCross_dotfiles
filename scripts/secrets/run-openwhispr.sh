#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
bws_guard "$@"

export VOICE_AGENT_KEY="${CODEX_PROXY_API_KEY:?Missing CODEX_PROXY_API_KEY}"
exec /usr/bin/openwhispr "$@"
