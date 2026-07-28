#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${BWS_SECRETS_INJECTED:-}" ]]; then
    exec "/home/lou/Documents/WorkFlow/envCross_dotfiles/scripts/secrets/run.sh" -- "$0" "$@"
fi
for arg in "$@"; do
    if [[ "$arg" == "trainer" && -n "${TRAINER_SLACK_APP_TOKEN:-}" ]]; then
        export SLACK_APP_TOKEN="$TRAINER_SLACK_APP_TOKEN"
        break
    fi
done
exec hermes "$@"
