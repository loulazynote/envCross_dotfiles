#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "--" ]] && shift
(( $# > 0 )) || { printf 'Usage: %s -- command [args...]\n' "$0" >&2; exit 2; }

token=$(secret-tool lookup service envcross-secrets key bws-access-token)
project_id=$(secret-tool lookup service envcross-secrets key bws-project-id)
[[ -n "$token" ]] || { printf 'Missing Bitwarden access token. Run scripts/secrets/configure.sh.\n' >&2; exit 1; }
[[ -n "$project_id" ]] || { printf 'Missing Bitwarden project ID. Run scripts/secrets/configure.sh.\n' >&2; exit 1; }

export BWS_ACCESS_TOKEN="$token"
exec bws run --project-id "$project_id" --output none -- env -u BWS_ACCESS_TOKEN BWS_SECRETS_INJECTED=1 "$@"
