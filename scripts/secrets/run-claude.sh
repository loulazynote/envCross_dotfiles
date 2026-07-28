#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${BWS_SECRETS_INJECTED:-}" ]]; then
    exec "/home/lou/Documents/WorkFlow/envCross_dotfiles/scripts/secrets/run.sh" -- "$0" "$@"
fi
provider=$(sqlite3 "$HOME/.cc-switch/cc-switch.db" "SELECT name FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1;")
case "$provider" in
    Nvidia) export ANTHROPIC_AUTH_TOKEN="${NVIDIA_API_KEY:?Missing NVIDIA_API_KEY}" ;;
    OpenCode) export ANTHROPIC_AUTH_TOKEN="${OPENCODE_API_KEY:?Missing OPENCODE_API_KEY}" ;;
    Codex) export ANTHROPIC_AUTH_TOKEN="${CODEX_PROXY_API_KEY:?Missing CODEX_PROXY_API_KEY}" ;;
    "Claude Official") unset ANTHROPIC_AUTH_TOKEN ;;
    *) printf 'Unsupported cc-switch Claude provider: %s\n' "$provider" >&2; exit 1 ;;
esac
exec "$HOME/.local/bin/claude" "$@"
