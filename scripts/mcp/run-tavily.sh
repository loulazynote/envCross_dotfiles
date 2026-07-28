#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
mcp_env_prepare TAVILY_API_KEY
: "${TAVILY_API_KEY:?Missing TAVILY_API_KEY}"
mcp_env_exec_npm tavily-mcp
