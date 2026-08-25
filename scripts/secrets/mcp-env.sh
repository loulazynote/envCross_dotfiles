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
    [[ ! -L "$dir" ]] || return 1
    if [[ -e "$dir" ]]; then
        [[ -d "$dir" && -O "$dir" ]] || return 1
    else
        mkdir -p -- "$dir" || return 1
    fi
    [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] || return 1
    chmod 700 -- "$dir" || return 1
}

mcp_env_cache_file_is_secure() {
    local mode links
    [[ -f "$MCP_ENV_CACHE" && ! -L "$MCP_ENV_CACHE" && -r "$MCP_ENV_CACHE" && -O "$MCP_ENV_CACHE" ]] || return 1
    mode=$(stat -c '%a' -- "$MCP_ENV_CACHE" 2>/dev/null) || return 1
    links=$(stat -c '%h' -- "$MCP_ENV_CACHE" 2>/dev/null) || return 1
    [[ "$links" == 1 ]] || return 1
    [[ "$mode" =~ ^[0-7]+$ ]] || return 1
    mode=$((8#$mode))
    (( (mode & 077) == 0 ))
}

mcp_env_load_cache() {
    mcp_env_cache_file_is_secure || return 1
    local line key value index
    local -a keys=() values=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" && "$line" != *$'\r'* && "$line" == *=* ]] || return 1
        key=${line%%=*}
        value=${line#*=}
        case "$key" in
            FIRECRAWL_API_KEY|MEM0_API_KEY|MEM0_AUTHORIZATION|CRAWL4AI_API_TOKEN|CRAWL4AI_SECRET_KEY|TAVILY_API_KEY|GITHUB_PERSONAL_ACCESS_TOKEN|OPENCODE_API_KEY|CODEX_PROXY_API_KEY|NVIDIA_API_KEY|BWS_SECRETS_INJECTED)
                ;;
            *)
                return 1
                ;;
        esac
        [[ " ${keys[*]} " != *" $key "* ]] || return 1
        if [[ "$key" == BWS_SECRETS_INJECTED && "$value" != 1 ]]; then
            return 1
        fi
        keys+=("$key")
        values+=("$value")
    done <"$MCP_ENV_CACHE"
    ((${#keys[@]} > 0)) || return 1
    for index in "${!keys[@]}"; do
        printf -v "${keys[index]}" '%s' "${values[index]}"
        export "${keys[index]}"
    done
    return 0
}

mcp_env_write_cache_from_env() {
    umask 077
    mcp_env_cache_dir || return 1
    if [[ -e "$MCP_ENV_CACHE" || -L "$MCP_ENV_CACHE" ]]; then
        mcp_env_cache_file_is_secure || return 1
    fi
    local tmp key
    tmp=$(mktemp -- "$MCP_ENV_CACHE.XXXXXX") || return 1
    {
        for key in "${MCP_ENV_KEYS[@]}"; do
            if [[ -n "${!key:-}" ]]; then
                [[ "${!key}" != *$'\n'* && "${!key}" != *$'\r'* ]] || {
                    rm -f -- "$tmp"
                    return 1
                }
                printf '%s=%s\n' "$key" "${!key}"
            fi
        done
        printf 'BWS_SECRETS_INJECTED=1\n'
    } >"$tmp"
    chmod 600 -- "$tmp" || {
        rm -f -- "$tmp"
        return 1
    }
    mv -f -- "$tmp" "$MCP_ENV_CACHE" || {
        rm -f -- "$tmp"
        return 1
    }
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
    local package="mcp-remote@0.1.38"
    exec npx -y "$package" "$@"
}

mcp_env_exec_npm() {
    (( $# > 0 )) || return 2
    local package="$1"
    shift
    case "$package" in
        firecrawl-mcp@3.24.0)
            ;;
        tavily-mcp@0.2.22)
            ;;
        *)
            printf 'Unsupported MCP package: %s\n' "$package" >&2
            return 2
            ;;
    esac
    exec npx -y "$package" "$@"
}
