# MCP configuration

Canonical non-secret config lives here.

## Files

| File | Use |
|------|-----|
| `cursor.mcp.json` | Cursor MCP JSON (`mcpServers`) |
| `ide.mcp.json` | VS Code MCP JSON (`servers`) |
| `cc-switch-mcp.json` | cc-switch MCP catalog seed, no secrets |

## Secret handling

User-managed service secrets live in one Bitwarden Secrets Manager project. Configure its read-only machine account locally:

```fish
scripts/secrets/configure.sh
```

The access token and project ID are stored in the desktop Secret Service keyring. `scripts/secrets/run.sh` retrieves them and uses `bws run` to inject secrets only into the launched process. Tool-owned OAuth sessions remain in their native stores.

Required secret names are `FIRECRAWL_API_KEY`, `MEM0_API_KEY`, `TAVILY_API_KEY`, `GITHUB_PERSONAL_ACCESS_TOKEN`, and `CRAWL4AI_API_TOKEN`.

Codex MCP children lack D-Bus, so wrappers use a local cache:

```fish
scripts/secrets/sync-mcp-env.sh
codex
```

Run the sync command from a desktop session after rotating secrets. `codex` refreshes the cache automatically. Cache path: `~/.cache/envcross/mcp.env` (mode `600`).

Also:

```fish
opencode
claude
with-secrets -- <cmd>
```

Grok Build reads MCP from `~/.grok/config.toml`, `~/.claude.json`, and `~/.mcp.json`. Keep all three aligned with the stdio wrappers.

Mem0 uses local stdio through `run-mem0.sh`. Set `MEM0_API_KEY`; the wrapper derives its authorization header without putting the token on the process argv.

Tavily uses local stdio through `run-tavily.sh` so BWS can inject `TAVILY_API_KEY`.

`sync-cc-switch-mcp.py` resolves `${env:NAME}` from environment. If an env var is missing, it preserves the existing cc-switch DB value for that field so stored secrets are not erased.

## Apply

```fish
./install.sh --no-install \
  --only-cursor-mcp \
  --only-cursor-user-mcp \
  --only-vscode-mcp \
  --only-cc-switch

scripts/mcp/sync-cc-switch-mcp.py
```

## Boundaries

- Cursor uses `mcpServers`; VS Code uses `servers`, so they cannot share one JSON shape.
- Zed uses `context_servers` inside `zed/settings.json`; it cannot consume the shared `mcp.json` directly.
- cc-switch app settings are symlinked from `ai-assistants/.cc-switch/settings.json`.
- cc-switch stores MCP servers in `~/.cc-switch/cc-switch.db`, not a symlink-friendly JSON file. The repo manages a seed JSON plus sync script, not the DB or auth files.

## Zed Firecrawl / MarkItDown

Use custom stdio servers so Bitwarden can inject secrets through wrapper scripts. If Zed shows duplicate Firecrawl or MarkItDown servers, uninstall the `mcp-server-firecrawl` and `mcp-server-markitdown` extensions from Zed.
