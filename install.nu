# Windows dotfiles installer via Scoop
# Tools: Windows Terminal, Nushell, Neovim, Yazi, Lazygit, Yasb, Komorebi, Whkd

def main [
    --dry-run (-n)          # Show what would be done without making changes
    --backup-only (-b)      # Backup existing configs only (no install/link)
    --no-backup             # Skip backup step
    --no-install            # Skip package installation
    --force-install         # Force reinstall packages
    --skip: any = []        # Skip specific tools (comma-separated or list)
    --only: any = []        # Only process specific tools
    --help (-h)             # Show this help
] {
    let current_file = ($env.CURRENT_FILE? | default "")
    let repo_root = if ($current_file | str length) > 0 { $current_file | path dirname } else { pwd }
    let windows_root = ($repo_root | path join "Windows")
    let backup_root = ($repo_root | path join $"backup/(date now | format date '%Y%m%d-%H%M%S')")

    let home = $env.USERPROFILE
    let appdata = $env.APPDATA
    let localappdata = $env.LOCALAPPDATA
    let user_config_home = ($home | path join ".config")

    def log_info  [msg: string] { print $"(ansi green)[INFO](ansi reset)  ($msg)" }
    def log_warn  [msg: string] { print $"(ansi yellow)[WARN](ansi reset)  ($msg)" }
    def log_error [msg: string] { print $"(ansi red)[ERROR](ansi reset) ($msg)" }
    def log_step  [msg: string] { print $"(ansi blue)[STEP](ansi reset)  ($msg)" }
    def log_dry   [msg: string] { print $"(ansi yellow)[DRY](ansi reset)   ($msg)" }

    def normalize_list [val: any]: nothing -> list<string> {
        if ($val == null) { return [] }
        let t = ($val | describe)
        if ($t | str starts-with "list") { return $val }
        if $t == "string" {
            let s = ($val | str trim)
            if ($s | str length) == 0 { return [] }
            if ($s | str contains ",") {
                return ($s | split row "," | each { $in | str trim } | where { $in | is-not-empty })
            }
            return [$s]
        }
        return [($val | into string)]
    }

    let skip_list = (normalize_list $skip)
    let only_list = (normalize_list $only)

    def should_install [tool: string, skip_list: list<string>, only_list: list<string>]: nothing -> bool {
        if ($only_list | is-not-empty) { return ($tool in $only_list) }
        return ($tool not-in $skip_list)
    }

    def check_cmd [cmd: string]: nothing -> bool {
        (which $cmd | is-not-empty)
    }

    def ensure_scoop [dry: bool]: nothing -> bool {
        if (check_cmd "scoop") {
            log_info "Scoop: already installed"
            return true
        }
        if $dry {
            log_dry "Would install Scoop"
            return true
        }
        log_info "Installing Scoop..."
        try {
            ^powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression"
            if (check_cmd "scoop") {
                log_info "Scoop: installed"
                try { ^scoop bucket add extras } catch { }
                return true
            } else {
                log_error "Scoop install failed"
                return false
            }
        } catch {
            log_error "Scoop install failed"
            return false
        }
    }

    def install_tool [tool: string, pkg: string, cmd: string, dry: bool, force: bool]: nothing -> bool {
        if (check_cmd $cmd) and (not $force) {
            log_info $"($tool): already installed"
            return true
        }
        if $dry {
            log_dry $"Would install: ($tool) ($pkg)"
            return true
        }
        if $force and (check_cmd $cmd) {
            log_info $"($tool): reinstalling (--force-install)"
        } else {
            log_info $"Installing ($tool)..."
        }
        try {
            ^scoop install $pkg
            if (check_cmd $cmd) {
                log_info $"($tool): installed"
                return true
            } else {
                log_warn $"($tool): package installed but command not found"
                return false
            }
        } catch {
            log_warn $"Failed to install ($tool)"
            return false
        }
    }

    def read_link_target [path: string]: nothing -> string {
        try {
            ^powershell -NoProfile -Command $"(Get-Item -LiteralPath '($path)' -Force -ErrorAction SilentlyContinue).Target" | str trim
        } catch {
            ""
        }
    }

    def remove_existing_path [path: string]: nothing -> bool {
        try {
            let script = '& { param([string]$Path) $ErrorActionPreference = "Stop"; $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue; if ($null -eq $item) { exit 0 }; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { if ($item.PSIsContainer) { [System.IO.Directory]::Delete($Path) } else { [System.IO.File]::Delete($Path) } } else { Remove-Item -LiteralPath $Path -Recurse -Force } }'
            let result = (^powershell -NoProfile -Command $script $path | complete)
            $result.exit_code == 0
        } catch {
            false
        }
    }

    def is_symlink [path: string]: nothing -> bool {
        let target = (read_link_target $path)
        ($target | str length) > 0
    }

    def backup [path: string, name: string, no_bak: bool, dry: bool, bak_root: string, repo_root: string] {
        if $no_bak or not ($path | path exists) { return }

        if (is_symlink $path) {
            log_info $"($name): existing symlink, skipping backup"
            return
        }

        let dest = ($bak_root | path join ($name | str replace --all '[/\\:*?"<>| ]' '_'))

        if $dry {
            log_dry $"Would backup: ($name)"
        } else {
            mkdir ($dest | path dirname)
            cp -r $path $dest
            log_info $"($name): backed up"
        }
    }

    def link_config [source: string, dest: string, is_file: bool, name: string, dry: bool] {
        if not ($source | path exists) {
            log_warn $"Source not found: ($name)"
            return
        }
        if $dry {
            log_dry $"Would link: ($name) -> ($dest)"
            return
        }
        let link_target = (read_link_target $dest)
        if ($dest | path exists) or (($link_target | str length) > 0) {
            if not (remove_existing_path $dest) {
                log_warn $"Failed to remove: ($dest)"
                return
            }
        }
        mkdir ($dest | path dirname)
        try {
            let result = (^powershell -NoProfile -Command $"New-Item -ItemType SymbolicLink -Path '($dest)' -Target '($source)' -Force | Out-Null" | complete)
            if $result.exit_code == 0 {
                log_info $"Linked: ($name) -> ($dest)"
                return
            }
            if not $is_file {
                let junction = (^cmd /c mklink /J $dest $source | complete)
                if $junction.exit_code == 0 {
                    log_info $"Linked with junction: ($name) -> ($dest)"
                    return
                }
            }
            log_error $"Failed to link: ($name)"
            log_warn "Enable Developer Mode: Settings → For developers → Developer Mode"
        } catch {
            log_error $"Failed to link: ($name)"
            log_warn "Enable Developer Mode: Settings → For developers → Developer Mode"
        }
    }

    def existing_targets [items: list<any>]: nothing -> list<any> {
        $items
        | where { |it| $it.src | path exists }
        | each { |it| {
            name: $it.name
            source: $it.src
            dest: $it.dest
            is_file: $it.is_file
        } }
    }

    def path_has_entries [path: string]: nothing -> bool {
        if not ($path | path exists) { return false }
        if (($path | path type) != "dir") { return true }
        try { ls -a $path | first | is-not-empty } catch { false }
    }

    def existing_non_empty_targets [items: list<any>]: nothing -> list<any> {
        existing_targets ($items | where { |it| path_has_entries $it.src })
    }

    def is_stub_link_candidate [source: string]: nothing -> bool {
        let name = ($source | path basename)
        ($name == ".system") or not ($name | str contains ".")
    }

    def resolve_link_source [source: string]: nothing -> record<source: string, is_file: bool, is_stub: bool> {
        if ($source | path type) == "dir" {
            return {
                source: $source
                is_file: false
                is_stub: false
            }
        }

        if not (is_stub_link_candidate $source) {
            return {
                source: $source
                is_file: true
                is_stub: false
            }
        }

        let raw_target = (try { open --raw $source | str trim } catch { "" })
        if (($raw_target | str starts-with "../") or ($raw_target | str starts-with "./")) {
            let resolved_target = (($source | path dirname) | path join $raw_target)
            if ($resolved_target | path exists) {
                return {
                    source: $resolved_target
                    is_file: (($resolved_target | path type) != "dir")
                    is_stub: true
                }
            }
        }

        {
            source: $source
            is_file: true
            is_stub: false
        }
    }

    def collect_link_targets [source_root: string, dest_root: string, name_prefix: string]: nothing -> list<any> {
        if not ($source_root | path exists) {
            return []
        }

        ls -a $source_root | each { |entry|
            let entry_name = ($entry.name | path basename)
            let resolved = (resolve_link_source $entry.name)
            {
                name: $"($name_prefix) ($entry_name)"
                source: $resolved.source
                dest: ($dest_root | path join $entry_name)
                is_file: $resolved.is_file
                is_stub: $resolved.is_stub
            }
        }
    }

    def ensure_real_dir [dest: string, name: string, dry: bool] {
        if $dry {
            log_dry $"Would ensure directory: ($name) -> ($dest)"
            return
        }

        let link_target = (read_link_target $dest)

        if (($link_target | str length) > 0) {
            if not (remove_existing_path $dest) {
                log_warn $"Failed to remove: ($dest)"
                return
            }
        } else if ($dest | path exists) and (($dest | path type) != "dir") {
            if not (remove_existing_path $dest) {
                log_warn $"Failed to remove: ($dest)"
                return
            }
        }

        if not ($dest | path exists) {
            mkdir $dest
        }
    }

    def decode_json_result [result: record, name: string] {
        if $result.exit_code != 0 {
            log_warn $"($name): command failed"
            return {
                ok: false
                value: null
            }
        }

        try {
            {
                ok: true
                value: ($result.stdout | from json)
            }
        } catch {
            log_warn $"($name): invalid JSON output"
            {
                ok: false
                value: null
            }
        }
    }

    def ensure_claude_local_plugin [marketplace_dir: string, dry: bool] {
        let marketplace_name = "lou-local-ai"
        let plugin_id = $"common-lsp@($marketplace_name)"

        if not ($marketplace_dir | path exists) {
            return
        }

        if $dry {
            log_dry $"Would ensure Claude marketplace: ($marketplace_name)"
            log_dry $"Would ensure Claude plugin: ($plugin_id)"
            return
        }

        let marketplaces_result = (decode_json_result
            (try { ^claude plugin marketplace list --json | complete } catch { {stdout: "[]", stderr: "", exit_code: 1} })
            "claude marketplace list"
        )
        if not $marketplaces_result.ok {
            return
        }
        let marketplaces = $marketplaces_result.value
        let has_marketplace = (($marketplaces | where { |it| (($it | get -o name | default "") == $marketplace_name) } | length) > 0)

        if not $has_marketplace {
            let add_result = (try { ^claude plugin marketplace add $marketplace_dir --scope user | complete } catch { {stdout: "", stderr: "", exit_code: 1} })
            if $add_result.exit_code == 0 {
                log_info $"claude marketplace: added ($marketplace_name)"
            } else {
                log_warn $"claude marketplace: failed to add ($marketplace_name)"
                return
            }
        } else {
            log_info $"claude marketplace: already added ($marketplace_name)"
        }

        let initial_plugins_result = (decode_json_result
            (try { ^claude plugin list --json | complete } catch { {stdout: "[]", stderr: "", exit_code: 1} })
            "claude plugin list"
        )
        if not $initial_plugins_result.ok {
            return
        }
        mut plugins = $initial_plugins_result.value

        let has_plugin = (($plugins | where { |it| (($it | get -o id | default "") == $plugin_id) } | length) > 0)
        if not $has_plugin {
            let install_result = (try { ^claude plugin install $plugin_id --scope user | complete } catch { {stdout: "", stderr: "", exit_code: 1} })
            if $install_result.exit_code == 0 {
                log_info $"claude plugin: installed ($plugin_id)"
                let refreshed_plugins_result = (decode_json_result
                    (try { ^claude plugin list --json | complete } catch { {stdout: "[]", stderr: "", exit_code: 1} })
                    "claude plugin list"
                )
                if not $refreshed_plugins_result.ok {
                    return
                }
                $plugins = $refreshed_plugins_result.value
            } else {
                log_warn $"claude plugin: failed to install ($plugin_id)"
                return
            }
        }

        let plugin_disabled = (($plugins | where { |it|
            (($it | get -o id | default "") == $plugin_id) and (($it | get -o enabled | default true) == false)
        } | length) > 0)
        if $plugin_disabled {
            let enable_result = (try { ^claude plugin enable $plugin_id --scope user | complete } catch { {stdout: "", stderr: "", exit_code: 1} })
            if $enable_result.exit_code == 0 {
                log_info $"claude plugin: enabled ($plugin_id)"
            } else {
                log_warn $"claude plugin: failed to enable ($plugin_id)"
            }
        } else {
            log_info $"claude plugin: ready ($plugin_id)"
        }
    }

    def ensure_yazi_config_layout [source: string, dry: bool] {
        let config_dir = ($source | path join "config")
        let entries = [
            {name: "init.lua",        is_file: true}
            {name: "keymap.toml",     is_file: true}
            {name: "package.toml",    is_file: true}
            {name: "theme.toml",      is_file: true}
            {name: "yazi.toml",       is_file: true}
            {name: "flavors",         is_file: false}
            {name: "plugins",         is_file: false}
            {name: "scripts",         is_file: false}
        ]

        if $dry {
            log_dry $"Would ensure Yazi Windows config links: ($config_dir)"
            return
        }

        mkdir $config_dir

        for entry in $entries {
            let src = ($source | path join $entry.name)
            let dest = ($config_dir | path join $entry.name)

            if not ($src | path exists) {
                log_warn $"Source not found: Yazi ($entry.name)"
                continue
            }
            if ($dest | path exists) {
                continue
            }

            try {
                let result = if $entry.is_file {
                    ^cmd /c mklink $dest $src | complete
                } else {
                    ^cmd /c mklink /D $dest $src | complete
                }
                if $result.exit_code == 0 {
                    log_info $"Linked: Yazi config ($entry.name)"
                } else {
                    log_warn $"Failed to link: Yazi config ($entry.name)"
                }
            } catch {
                log_warn $"Failed to link: Yazi config ($entry.name)"
            }
        }
    }

    print "============================================"
    print "  Windows Dotfiles Installer"
    print "============================================"
    print ""
    print $"Repository: ($repo_root)"
    print ""

    let is_admin = (try { (^net session | complete | get exit_code) == 0 } catch { false })
    if not $is_admin {
        log_warn "Not running as Administrator"
        log_warn "Symlinks require Admin or Developer Mode"
        print ""
    }

    if $dry_run { log_warn "DRY RUN MODE - No changes will be made" }

    # === Step 1: Install Tools ===
    if not $no_install and not $backup_only {
        print ""
        log_step "=== Step 1: Installing Tools ==="
        print ""

        if not (ensure_scoop $dry_run) {
            log_error "Scoop required"
            return
        }

        let tools = [
            {name: "Windows-Terminal",  pkg: "windows-terminal",  cmd: "wt"}
            {name: "WezTerm",           pkg: "wezterm",           cmd: "wezterm"}
            {name: "Nushell",           pkg: "nu",                cmd: "nu"}
            {name: "Neovim",            pkg: "neovim",            cmd: "nvim"}
            {name: "Helix",              pkg: "helix",             cmd: "hx"}
            {name: "Zed",                pkg: "zed",               cmd: "zed"}
            {name: "Yazi",              pkg: "yazi",              cmd: "yazi"}
            {name: "mpv",               pkg: "mpv",               cmd: "mpv"}
            {name: "yt-dlp",            pkg: "yt-dlp",            cmd: "yt-dlp"}
            {name: "Lazygit",           pkg: "lazygit",           cmd: "lazygit"}
            {name: "Yasb",              pkg: "yasb",              cmd: "yasb"}
            {name: "Komorebi",          pkg: "komorebi",          cmd: "komorebi"}
            {name: "Whkd",              pkg: "whkd",              cmd: "whkd"}
        ]

        for tool in $tools {
            if (should_install ($tool.name | str lowercase) $skip_list $only_list) {
                install_tool $tool.name $tool.pkg $tool.cmd $dry_run $force_install
            }
        }
    }

    # === Step 2: Build targets ===
    mut targets = []
    let scoop_root = ($env.SCOOP? | default "")

    if (should_install "windows-terminal" $skip_list $only_list) {
        mut wt_src = ($windows_root | path join "windows terminal" | path join "settings.json")
        if not ($wt_src | path exists) {
            let fallback = ($repo_root | path join "windows terminal" | path join "settings.json")
            if ($fallback | path exists) {
                log_warn "Windows Terminal settings missing under Windows/; using repo root fallback"
                $wt_src = $fallback
            }
        }
        if ($scoop_root | str length) == 0 {
            log_warn "SCOOP env not set; skipping Windows Terminal linking"
        } else {
            $targets ++= [{
                name: "Windows Terminal"
                source: $wt_src
                dest: ($scoop_root | path join "apps" | path join "windows-terminal" | path join "current" | path join "settings" | path join "settings.json")
                is_file: true
            }]
        }
    }

    if (should_install "wezterm" $skip_list $only_list) {
        $targets ++= [{
            name: "WezTerm"
            source: ($windows_root | path join "wezterm" | path join "wezterm.lua")
            dest: ($home | path join ".wezterm.lua")
            is_file: true
        }]
    }

    if (should_install "mpv" $skip_list $only_list) {
        if ($scoop_root | str length) == 0 {
            log_warn "SCOOP env not set; skipping mpv linking"
        } else {
            let mpv_source = ($windows_root | path join "mpv")
            let mpv_config = ($scoop_root | path join "persist" | path join "mpv" | path join "portable_config")
            $targets ++= [
                {
                    name: "mpv config"
                    source: ($mpv_source | path join "mpv.conf")
                    dest: ($mpv_config | path join "mpv.conf")
                    is_file: true
                }
                {
                    name: "mpv profiles"
                    source: ($mpv_source | path join "profiles.conf")
                    dest: ($mpv_config | path join "profiles.conf")
                    is_file: true
                }
            ]
        }
    }

    if (should_install "powershell" $skip_list $only_list) {
        mut pwsh_profile = ($windows_root | path join "powershell" | path join "Microsoft.PowerShell_profile.ps1")
        if not ($pwsh_profile | path exists) {
            let fallback = ($repo_root | path join "powershell" | path join "Microsoft.PowerShell_profile.ps1")
            if ($fallback | path exists) {
                log_warn "PowerShell profile missing under Windows/; using repo root fallback"
                $pwsh_profile = $fallback
            }
        }
        if ($pwsh_profile | path exists) {
            $targets ++= [{
                name: "PowerShell profile"
                source: $pwsh_profile
                dest: ($home | path join "Documents" | path join "PowerShell" | path join "Microsoft.PowerShell_profile.ps1")
                is_file: true
            }]
        }
    }

    if (should_install "nushell" $skip_list $only_list) {
        let nu_src = if (($windows_root | path join "nushell") | path exists) {
            $windows_root | path join "nushell"
        } else {
            log_warn "Nushell dir missing under Windows/; using repo root fallback"
            $repo_root | path join "nushell"
        }
        $targets ++= [{
            name: "Nushell"
            source: $nu_src
            dest: ($appdata | path join "nushell")
            is_file: false
        }]
    }

    if (should_install "neovim" $skip_list $only_list) {
        $targets ++= [{
            name: "Neovim"
            source: ($repo_root | path join "nvim")
            dest: ($localappdata | path join "nvim")
            is_file: false
        }]
    }

    if (should_install "helix" $skip_list $only_list) {
        let helix_files = [
            {src: ($repo_root | path join "helix" | path join "config.toml"), dest: ($appdata | path join "helix" | path join "config.toml"), is_file: true, name: "Helix config"}
            {src: ($repo_root | path join "helix" | path join "languages.windows.toml"), dest: ($appdata | path join "helix" | path join "languages.toml"), is_file: true, name: "Helix languages"}
        ]
        $targets ++= (existing_targets $helix_files)
    }

    if (should_install "zed" $skip_list $only_list) {
        let generated_zed_settings = ($localappdata | path join "envCross_dotfiles" | path join "zed" | path join "settings.json")
        if $dry_run {
            log_dry $"Would render: Zed settings -> ($generated_zed_settings)"
        } else {
            mkdir ($generated_zed_settings | path dirname)
            ^python ($repo_root | path join "scripts" | path join "merge-json.py") ($repo_root | path join "zed" | path join "settings.json") ($repo_root | path join "zed" | path join "lsp.windows.json") $generated_zed_settings
        }
        let zed_files = [
            {src: $generated_zed_settings, dest: ($appdata | path join "Zed" | path join "settings.json"), is_file: true, name: "Zed settings"}
            {src: ($repo_root | path join "zed" | path join "keymap.json"), dest: ($appdata | path join "Zed" | path join "keymap.json"), is_file: true, name: "Zed keymap"}
        ]
        $targets ++= (existing_targets $zed_files)
    }

    if (should_install "yazi" $skip_list $only_list) {
        let yazi_src = ($repo_root | path join "yazi")
        if not $backup_only {
            ensure_yazi_config_layout $yazi_src $dry_run
        }
        $targets ++= [{
            name: "Yazi"
            source: $yazi_src
            dest: ($appdata | path join "yazi")
            is_file: false
        }]
    }

    if (should_install "lazygit" $skip_list $only_list) {
        $targets ++= [{
            name: "Lazygit"
            source: ($repo_root | path join "lazygit")
            dest: ($localappdata | path join "lazygit")
            is_file: false
        }]
    }

    let yasb_config_dir = ($user_config_home | path join "yasb")
    if (should_install "yasb" $skip_list $only_list) {
        let yasb_src = ($windows_root | path join "yasb")
        let yasb_files = [
            {src: ($yasb_src | path join "config.yaml"), dest: ($yasb_config_dir | path join "config.yaml"), is_file: true, name: "Yasb config.yaml"}
            {src: ($yasb_src | path join "styles.css"),  dest: ($yasb_config_dir | path join "styles.css"),  is_file: true, name: "Yasb styles.css"}
        ]
        $targets ++= (existing_targets $yasb_files)
    }

    if (should_install "komorebi" $skip_list $only_list) {
        let komorebi_src = ($windows_root | path join "komorebi")
        let komorebi_files = [
            {src: ($komorebi_src | path join "komorebi.json"),     dest: ($home | path join "komorebi.json"),     is_file: true, name: "Komorebi config"}
            {src: ($komorebi_src | path join "komorebi.bar.json"), dest: ($home | path join "komorebi.bar.json"), is_file: true, name: "Komorebi bar config"}
            {src: ($komorebi_src | path join "applications.json"), dest: ($home | path join "applications.json"), is_file: true, name: "Komorebi applications"}
        ]
        $targets ++= (existing_targets $komorebi_files)
    }

    let link_whkd = ("whkd" not-in $skip_list) and ((should_install "komorebi" $skip_list $only_list) or (should_install "whkd" $skip_list $only_list))
    if $link_whkd {
        let whkd_files = [
            {src: ($windows_root | path join "whkd" | path join "whkdrc"), dest: ($user_config_home | path join "whkdrc"), is_file: true, name: "WHKD config"}
        ]
        $targets ++= (existing_targets $whkd_files)
    }

    # AI tools
    let ai_root      = ($repo_root | path join "ai-assistants")
    let claude_root  = ($ai_root   | path join ".claude")
    let shared_agents = ($ai_root  | path join "AGENTS.md")
    let shared_skills = ($ai_root  | path join "SKILLS")
    let shared_hooks = ($ai_root  | path join "hooks")
    let claude_home = ($home | path join ".claude")
    let codex_home = ($home | path join ".codex")
    let grok_home = ($home | path join ".grok")
    let opencode_home = ($user_config_home | path join "opencode")
    let gemini_home = ($home | path join ".gemini")
    let has_claude = (check_cmd "claude")
    let has_codex = (check_cmd "codex")
    let has_grok = (check_cmd "grok")
    let has_opencode = (check_cmd "opencode")
    let has_gemini = (check_cmd "gemini")
    let has_hermes = (check_cmd "hermes")
    let should_link_claude = $has_claude and (should_install "claude-code" $skip_list $only_list)
    let should_link_codex = $has_codex and (should_install "codex" $skip_list $only_list)
    let should_link_grok = $has_grok and (should_install "grok" $skip_list $only_list)
    let should_link_opencode = $has_opencode and (should_install "opencode" $skip_list $only_list)
    let should_link_gemini = $has_gemini and (should_install "gemini-cli" $skip_list $only_list)
    let should_link_hermes = $has_hermes and (should_install "hermes-agent" $skip_list $only_list)
    let claude_agents = ($claude_root | path join "agents")
    let claude_rules  = ($claude_root | path join "rules")
    let claude_statusline = ($claude_root | path join "statusline-command.sh")
    let claude_marketplace = ($claude_root | path join "marketplace")
    let claude_skills_dest = ($claude_home | path join "skills")
    let resolved_claude_skill_targets = if $should_link_claude {
        collect_link_targets $shared_skills $claude_skills_dest ".claude skill"
    } else {
        []
    }
    let should_expand_claude_skills = (($resolved_claude_skill_targets | where { |it| $it.is_stub } | length) > 0)
    let active_claude_skill_targets = if $should_expand_claude_skills {
        $resolved_claude_skill_targets | each { |it| {
            name: $it.name
            source: $it.source
            dest: $it.dest
            is_file: $it.is_file
        } }
    } else {
        []
    }

    if $should_link_claude {
        let claude_files = [
            {src: ($claude_root | path join "CLAUDE.md"),      dest: ($claude_home | path join "CLAUDE.md"),               is_file: true,  name: ".claude CLAUDE.md"}
            {src: ($claude_root | path join "settings.json"),  dest: ($claude_home | path join "settings.json"),           is_file: true,  name: ".claude settings"}
            {src: $shared_hooks,                               dest: ($claude_home | path join "hooks"),                   is_file: false, name: ".claude hooks"}
            {src: $claude_statusline,                          dest: ($claude_home | path join "statusline-command.sh"),   is_file: true,  name: ".claude statusline"}
        ]
        $targets ++= (existing_targets $claude_files)
        $targets ++= (existing_non_empty_targets [
            {src: $claude_agents,      dest: ($claude_home | path join "agents"),      is_file: false, name: ".claude agents"}
            {src: $claude_rules,       dest: ($claude_home | path join "rules"),       is_file: false, name: ".claude rules"}
            {src: $claude_marketplace, dest: ($claude_home | path join "marketplace"), is_file: false, name: ".claude marketplace"}
        ])
        if $should_expand_claude_skills {
            $targets ++= $active_claude_skill_targets
        } else {
            $targets ++= [{
                name: ".claude skills"
                source: $shared_skills
                dest: $claude_skills_dest
                is_file: false
            }]
        }
    }

    let codex_config = ($windows_root | path join "codex" | path join "config.toml")
    if $should_link_codex {
        let codex_files = [
            {src: $shared_agents,  dest: ($codex_home | path join "AGENTS.md"),   is_file: true,  name: "Codex AGENTS.md"}
            {src: $codex_config,   dest: ($codex_home | path join "config.toml"), is_file: true,  name: "Codex config.toml"}
            {src: $shared_skills,  dest: ($codex_home | path join "skills"),      is_file: false, name: "Codex skills"}
        ]
        $targets ++= (existing_targets $codex_files)
    }

    if $should_link_grok {
        $targets ++= (existing_targets [{
            src: ($ai_root | path join ".grok" | path join "config.toml")
            dest: ($grok_home | path join "config.toml")
            is_file: true
            name: "Grok config.toml"
        }])
    }

    if $should_link_opencode {
        let opencode_files = [
            {src: $shared_agents, dest: ($opencode_home | path join "AGENTS.md"),    is_file: true,  name: "opencode AGENTS.md"}
            {src: ($ai_root | path join ".opencode" | path join "opencode.json"),     dest: ($opencode_home | path join "opencode.json"), is_file: true,  name: "opencode config"}
            {src: ($ai_root | path join ".opencode" | path join "tui.json"),          dest: ($opencode_home | path join "tui.json"),      is_file: true,  name: "opencode tui"}
            {src: $shared_skills, dest: ($opencode_home | path join "skills"),        is_file: false, name: "opencode skills"}
            {src: ($ai_root | path join ".opencode" | path join "agents"),            dest: ($opencode_home | path join "agents"),        is_file: false, name: "opencode agents"}
            {src: ($ai_root | path join ".opencode" | path join "commands"),          dest: ($opencode_home | path join "commands"),      is_file: false, name: "opencode commands"}
            {src: ($ai_root | path join ".opencode" | path join "plugins"),           dest: ($opencode_home | path join "plugins"),       is_file: false, name: "opencode plugins"}
            {src: ($ai_root | path join ".opencode" | path join "enforce-shell-policy.sh"), dest: ($opencode_home | path join "enforce-shell-policy.sh"), is_file: true, name: "opencode shell policy"}
        ]
        $targets ++= (existing_targets $opencode_files)
    }

    let gemini_md = ($ai_root | path join ".gemini" | path join "GEMINI.md")
    if $should_link_gemini and ($gemini_md | path exists) {
        $targets ++= [{
            name: ".gemini GEMINI.md"
            source: $gemini_md
            dest: ($gemini_home | path join "GEMINI.md")
            is_file: true
        }]
    }

    let hermes_home = ($home | path join ".hermes")
    let hermes_files = [
        {src: ($ai_root | path join ".hermes" | path join "SOUL.md"),      dest: ($hermes_home | path join "SOUL.md"),      is_file: true,  name: "Hermes SOUL.md"}
        {src: ($ai_root | path join ".hermes" | path join "config.yaml"),  dest: ($hermes_home | path join "config.yaml"),  is_file: true,  name: "Hermes config.yaml"}
        {src: ($ai_root | path join ".hermes" | path join "hooks"),        dest: ($hermes_home | path join "hooks"),        is_file: false, name: "Hermes hooks"}
    ]
    if $should_link_hermes {
        $targets ++= (existing_targets $hermes_files)
    }

    # === Step 2: Backup ===
    if not $no_backup {
        print ""
        log_step "=== Step 2: Backing Up Existing Configs ==="
        print ""

        if not $dry_run { mkdir $backup_root }

        for t in $targets {
            backup $t.dest $t.name $no_backup $dry_run $backup_root $repo_root
        }
    }

    if $backup_only {
        print ""
        if not $dry_run and ($backup_root | path exists) {
            log_info $"Backup complete: ($backup_root)"
        }
        return
    }

    # === Step 3: Link Configs ===
    print ""
    log_step "=== Step 3: Creating Links ==="
    print ""

    if ($active_claude_skill_targets | is-not-empty) {
        ensure_real_dir $claude_skills_dest ".claude skills" $dry_run
    }
    if (should_install "yasb" $skip_list $only_list) {
        ensure_real_dir $yasb_config_dir "Yasb config dir" $dry_run
    }

    for t in $targets {
        link_config $t.source $t.dest $t.is_file $t.name $dry_run
    }

    if $should_link_claude {
        ensure_claude_local_plugin $claude_marketplace $dry_run
    }

    # === Done ===
    print ""
    log_step "=== Installation Complete ==="
    print ""

    if $dry_run {
        log_info "Dry run completed. No changes were made."
        return
    }

    if (should_install "neovim" $skip_list $only_list) and (check_cmd "nvim") {
        print "  Open Neovim to install plugins: nvim"
    }
    if (should_install "nushell" $skip_list $only_list) and (check_cmd "nu") {
        print "  Set Nushell as default: scoop install nu"
    }

    print ""
    if ($backup_root | path exists) {
        log_info $"Backups saved to: ($backup_root)"
    }
    print ""
    print "Restart your terminal to apply changes."
}
