# Dotfiles

A cross-platform dotfiles repository for Linux and Windows, featuring centralized configuration management and shared AI assistant instructions.

## 🚀 Installation

### Linux
Linux installation targets are defined in `config/targets.manifest`. The installer supports different scopes (`linux`, `shared`, `ai`) and groups (`core`, `niri`, `utilities`, `config`, `ai`).

```bash
# Full installation
./install.sh

# View available options and targets
./install.sh --help

# Advanced usage examples
./install.sh --dry-run
./install.sh --no-install
./install.sh --skip-kitty
./install.sh --only-neovim
./install.sh --only-lazysql
```

System-level Linux fixes that write to `/etc` are tracked separately under `Linux-system/` and are not part of the regular `install.sh` symlink flow.

```bash
bash ./scripts/install-udev-rules.sh
```

### Windows
```powershell
# Full installation
nu install.nu

# Advanced usage examples
nu install.nu --dry-run
nu install.nu --skip [yasb]
nu install.nu --only [nvim lazygit]
```

## 🤖 AI Assistant Configuration

This repository centralizes assistant context and tool-specific settings under `ai-assistants/`. Shared rules live in `ai-assistants/AGENTS.md`; shared skills live in `ai-assistants/SKILLS/`; tool-specific files live in hidden subdirectories such as `ai-assistants/.claude` and `ai-assistants/.opencode`.

### Directory Structure
```text
ai-assistants/
├── AGENTS.md
├── AGENTS.12-rules.backup.md
├── SKILLS/
├── .claude/
│   ├── CLAUDE.md
│   ├── agents/
│   ├── hooks/
│   ├── marketplace/
│   ├── rules/
│   ├── settings.json
│   ├── skills/
│   └── statusline-command.sh
├── .codex/
│   └── config.toml
├── .gemini/
│   └── GEMINI.md
├── .grok/
│   └── config.toml
├── .hermes/
│   ├── SOUL.md
│   ├── config.yaml
│   └── hooks/
├── .opencode/
│   ├── agents/
│   ├── commands/
│   ├── plugins/
│   ├── enforce-shell-policy.sh
│   ├── opencode.json
│   └── tui.json
└── mcp/
```

### Installation Targets
During installation, these files are linked to the appropriate locations for each tool:

| AI Tool | Source | Target Path |
|---------|--------|-------------|
| **Claude Code** | `ai-assistants/.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| **Claude Code** | `ai-assistants/.claude/settings.json` | `~/.claude/settings.json` |
| **Claude Code** | `ai-assistants/.claude/agents/` | `~/.claude/agents` |
| **Claude Code** | `ai-assistants/hooks/` | `~/.claude/hooks` |
| **Claude Code** | `ai-assistants/.claude/rules/` | `~/.claude/rules` |
| **Claude Code** | `ai-assistants/SKILLS/` | `~/.claude/skills` |
| **Claude Code** | `ai-assistants/.claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| **Claude Code** | `ai-assistants/.claude/marketplace/` | `~/.claude/marketplace` |
| **Codex** | `ai-assistants/AGENTS.md` | `~/.codex/AGENTS.md` |
| **Codex** | `ai-assistants/.codex/config.toml` | `~/.codex/config.toml` |
| **Codex** | `ai-assistants/.codex/windows.config.toml` | `~/.codex/windows.config.toml` |
| **Codex** | `ai-assistants/.codex/linux.config.toml` | `~/.codex/linux.config.toml` |
| **Codex** | `ai-assistants/.codex/hooks.json` | `~/.codex/hooks.json` |
| **Codex** | `ai-assistants/.codex/agents/` | `~/.codex/agents` |
| **Codex** | `ai-assistants/SKILLS/` | `~/.codex/skills` |
| **Grok Build** | `ai-assistants/AGENTS.md` | `~/.grok/AGENTS.md` |
| **Grok Build** | `ai-assistants/.grok/config.toml` | `~/.grok/config.toml` |
| **OpenCode** | `ai-assistants/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| **OpenCode** | `ai-assistants/.opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| **OpenCode** | `ai-assistants/.opencode/tui.json` | `~/.config/opencode/tui.json` |
| **OpenCode** | `ai-assistants/.opencode/agents/` | `~/.config/opencode/agents` |
| **OpenCode** | `ai-assistants/.opencode/commands/` | `~/.config/opencode/commands` |
| **OpenCode** | `ai-assistants/.opencode/plugins/` | `~/.config/opencode/plugins` |
| **OpenCode** | `ai-assistants/.opencode/enforce-shell-policy.sh` | `~/.config/opencode/enforce-shell-policy.sh` |
| **OpenCode** | `ai-assistants/SKILLS/` | `~/.config/opencode/skills` |
| **Gemini CLI** | `ai-assistants/.gemini/GEMINI.md` | `~/.gemini/GEMINI.md` |
| **Hermes** | `ai-assistants/.hermes/SOUL.md` | `~/.hermes/SOUL.md` |
| **Hermes** | `ai-assistants/.hermes/config.yaml` | `~/.hermes/config.yaml` |
| **Hermes** | `ai-assistants/.hermes/hooks/` | `~/.hermes/hooks` |

### MCP Configuration

Shared MCP config lives under `ai-assistants/mcp/`. Cursor and VS Code use separate JSON shapes from the same catalog intent. Zed uses its own `context_servers` section inside `zed/settings.json`. cc-switch MCP servers are synced into its SQLite DB from a secret-free catalog.

```bash
bash ./install.sh --no-install --only-cursor-mcp --only-cursor-user-mcp --only-vscode-mcp --only-cc-switch
scripts/mcp/sync-cc-switch-mcp.py
```

Secrets stay outside git in `~/.config/mcp/secrets.env`; see `ai-assistants/mcp/README.md`.

## 📁 Paths & Configuration

### Linux
Linux configuration sources live primarily under the `Linux-config/` directory. 
- Non-XDG files (e.g., `.profile`) remain at the repository root.
- `~/.local/share` targets live under `Linux-local-share/`.
- System-level files that target paths such as `/etc/udev/rules.d` live under `Linux-system/`.
- App-managed state files that frequently rewrite themselves (e.g., `waypaper/config.ini`, `fcitx5` runtime state) are intentionally unmanaged to avoid repository drift.

<details>
<summary><b>View Linux Configuration Paths</b></summary>

| Tool | Target Path |
|------|-------------|
| **niri** | `~/.config/niri/config.kdl` |
| **kitty** | `~/.config/kitty` |
| **ghostty** | `~/.config/ghostty` |
| **autostart** | `~/.config/autostart` |
| **fcitx5** | `~/.config/fcitx5` |
| **fish** | `~/.config/fish` |
| **direnv** | `~/.config/direnv` |
| **neovim** | `~/.config/nvim` |
| **helix** | `~/.config/helix` |
| **zed** | `~/.config/zed` |
| **yazi** | `~/.config/yazi` |
| **lazygit** | `~/.config/lazygit` |
| **lazysql** | `~/.config/lazysql` |
| **tock** | `~/.config/tock` |
| **zellij** | `~/.config/zellij` |
| **systemd-user** | `~/.config/systemd/user` |
| **waybar** | `~/.config/waybar` |
| **vicinae** | `~/.config/vicinae` |
| **pcmanfm-qt** | `~/.config/pcmanfm-qt` |
| **hyprlock** | `~/.config/hypr` |
| **zathura** | `~/.config/zathura` |
| **easyeffects** | `~/.config/easyeffects` |
| **mpv** | `~/.config/mpv` |
| **pipewire** | `~/.config/pipewire` |
| **qt6ct** | `~/.config/qt6ct` |
| **qt6ct-env** | `~/.config/environment.d/qt6ct.conf` |
| **mimeapps** | `~/.config/mimeapps.list` |
| **niri-mimeapps**| `~/.config/niri-mimeapps.list` |
| **satty-config** | `~/.config/satty` |
| **wireplumber** | `~/.config/wireplumber` |
| **xdg-terminals**| `~/.config/xdg-terminals.list` |
| **xdg-desktop-portal** | `~/.config/xdg-desktop-portal` |
| **niri-xdg-terminals** | `~/.config/niri-xdg-terminals.list` |
| **user-dirs** | `~/.config/user-dirs.dirs` |
| **user-dirs-locale** | `~/.config/user-dirs.locale` |
| **profile** | `~/.profile` |
| **kitty-desktop**| `~/.local/share/applications/kitty.desktop` |
| **gitconfig** | `~/.gitconfig` |

</details>

### Windows
Windows Terminal, WezTerm, Nushell, Neovim, Yazi, MPV, Codex, Lazygit, Yasb, Komorebi, and Whkd configurations are supported.

<details>
<summary><b>View Windows Configuration Paths</b></summary>

| Tool | Target Path |
|------|-------------|
| **windows terminal** | `%SCOOP%\apps\windows-terminal\current\settings\settings.json` |
| **wezterm** | `%USERPROFILE%\.config\wezterm\wezterm.lua` |
| **powershell** | `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` |
| **nushell** | `%APPDATA%\nushell` |
| **neovim** | `%LOCALAPPDATA%\nvim` |
| **yazi** | `%APPDATA%\yazi` |
| **mpv** | `%SCOOP%\persist\mpv\portable_config` |
| **codex** | `%USERPROFILE%\.codex\config.toml` |
| **lazygit** | `%LOCALAPPDATA%\lazygit` |
| **yasb** | `%USERPROFILE%\.config\yasb\config.yaml` |
| **yasb** | `%USERPROFILE%\.config\yasb\styles.css` |
| **komorebi** | `%USERPROFILE%\komorebi.json` |
| **komorebi** | `%USERPROFILE%\komorebi.bar.json` |
| **komorebi** | `%USERPROFILE%\applications.json` |
| **whkd** | `%USERPROFILE%\.config\whkdrc` |

</details>
