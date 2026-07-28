#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"
mcp_env_prepare GITHUB_PERSONAL_ACCESS_TOKEN
: "${GITHUB_PERSONAL_ACCESS_TOKEN:?Missing GITHUB_PERSONAL_ACCESS_TOKEN}"
exec docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
