#!/usr/bin/env bash
set -euo pipefail

read -rsp "Bitwarden machine access token: " token
printf '\n'
read -rp "Bitwarden project ID: " project_id

[[ -n "$token" && -n "$project_id" ]]
BWS_ACCESS_TOKEN="$token" bws project get "$project_id" --output none
printf '%s' "$token" | secret-tool store --label="envCross Bitwarden access token" service envcross-secrets key bws-access-token
printf '%s' "$project_id" | secret-tool store --label="envCross Bitwarden project ID" service envcross-secrets key bws-project-id
unset token
printf 'Bitwarden Secrets Manager configured.\n'
