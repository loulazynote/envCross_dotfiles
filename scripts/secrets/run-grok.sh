#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/secrets/mcp-env.sh"

source_config="$(mcp_env_root)/ai-assistants/.grok/config.toml"
target_config="$HOME/.grok/config.toml"

restore_config() {
    ln -sfn "$source_config" "$target_config"
}

mkdir -p "${target_config%/*}"
restore_config
trap restore_config EXIT

bws_guard "$@"
exec "$HOME/.grok/bin/grok" "$@"
