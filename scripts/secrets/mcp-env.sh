#!/usr/bin/env bash
MCP_ENV_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/envcross/mcp.env"
MCP_ENV_KEYS=(
    FIRECRAWL_API_KEY
    MEM0_API_KEY
    MEM0_AUTHORIZATION
    CRAWL4AI_API_TOKEN
    CRAWL4AI_SECRET_KEY
    TAVILY_API_KEY
    GITHUB_PERSONAL_ACCESS_TOKEN
    OPENCODE_API_KEY
    CODEX_PROXY_API_KEY
    NVIDIA_API_KEY
)

mcp_env_root() {
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd
}

mcp_env_cache_dir() {
    local dir
    dir=$(dirname -- "$MCP_ENV_CACHE")
    mkdir -p -- "$dir"
    chmod 700 -- "$dir" 2>/dev/null || true
}

mcp_env_load_cache() {
    [[ -f "$MCP_ENV_CACHE" && -r "$MCP_ENV_CACHE" ]] || return 1
    set -a
    # shellcheck disable=SC1090
    source "$MCP_ENV_CACHE"
    set +a
    return 0
}

mcp_env_write_cache_from_env() {
    mcp_env_cache_dir
    local tmp key
    tmp=$(mktemp -- "$MCP_ENV_CACHE.XXXXXX")
    umask 077
    {
        for key in "${MCP_ENV_KEYS[@]}"; do
            if [[ -n "${!key:-}" ]]; then
                printf 'export %s=%q\n' "$key" "${!key}"
            fi
        done
        printf 'export BWS_SECRETS_INJECTED=1\n'
    } >"$tmp"
    chmod 600 -- "$tmp"
    mv -f -- "$tmp" "$MCP_ENV_CACHE"
}

mcp_env_sync() {
    local root
    root=$(mcp_env_root)
    "$root/scripts/secrets/sync-mcp-env.sh" >/dev/null
}

mcp_env_has_all() {
    local key
    for key in "$@"; do
        [[ -n "${!key:-}" ]] || return 1
    done
    return 0
}

mcp_env_prepare() {
    (( $# > 0 )) || return 2
    if mcp_env_has_all "$@"; then
        export BWS_SECRETS_INJECTED="${BWS_SECRETS_INJECTED:-1}"
        return 0
    fi
    if mcp_env_load_cache && mcp_env_has_all "$@"; then
        return 0
    fi
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" || -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        if mcp_env_sync 2>/dev/null && mcp_env_load_cache && mcp_env_has_all "$@"; then
            return 0
        fi
    fi
    printf 'Missing secrets for: %s\n' "$*" >&2
    printf 'Run: %s/scripts/secrets/sync-mcp-env.sh\n' "$(mcp_env_root)" >&2
    printf 'Codex MCP has no D-Bus; cache secrets first, then restart Codex.\n' >&2
    return 1
}

bws_guard() {
    if [[ -z "${BWS_SECRETS_INJECTED:-}" ]]; then
        local root
        root=$(mcp_env_root)
        exec "$root/scripts/secrets/run.sh" -- "$0" "$@"
    fi
}

mcp_env_exec_remote() {
    local bin="${MCP_NODE_PREFIX:-$HOME/.local/share/mcp-node}/node_modules/.bin/mcp-remote"
    if [[ -x "$bin" ]]; then
        exec "$bin" "$@"
    fi
    exec npx -y mcp-remote "$@"
}

mcp_env_exec_npm() {
    local name="$1" bin
    shift
    bin="${MCP_NODE_PREFIX:-$HOME/.local/share/mcp-node}/node_modules/.bin/$name"
    if [[ -x "$bin" ]]; then
        exec "$bin" "$@"
    fi
    exec npx -y "$name@latest" "$@"
}
