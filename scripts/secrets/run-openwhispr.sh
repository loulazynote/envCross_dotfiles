#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
bws_guard "$@"

export CUSTOM_CLEANUP_API_KEY="${OPENCODE_API_KEY:?Missing OPENCODE_API_KEY}"
exec /usr/bin/openwhispr "$@"
