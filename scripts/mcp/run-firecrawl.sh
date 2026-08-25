#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
mcp_env_prepare FIRECRAWL_API_KEY
: "${FIRECRAWL_API_KEY:?Missing FIRECRAWL_API_KEY}"
mcp_env_exec_npm firecrawl-mcp@3.24.0
