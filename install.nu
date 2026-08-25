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

    def powershell_host []: nothing -> string {
        if (check_cmd "pwsh") { "pwsh" } else { "powershell" }
    }

    def --env ensure_scoop [dry: bool, elevated: bool]: nothing -> bool {
        if (check_cmd "scoop") {
            log_info "Scoop: already installed"
            return true
        }
        if $dry {
            log_dry "Would install Scoop"
            return true
        }
        log_info "Installing Scoop..."
        let install_url = "https://raw.githubusercontent.com/ScoopInstaller/Install/3bcaeb2ea53ad611fd8552eb9f735c5e2cd52f40/install.ps1"
        let expected_hash = "84242117FBD6CF80C1F1767E590A681257DB47E8E0E6864DC445CE6C7FD6980E"
        let temp_script = (mktemp --suffix ".ps1")
        try {
            http get --raw $install_url | save --raw --force $temp_script
            let actual_hash = (open --raw $temp_script | hash sha256 | str uppercase)
            if $actual_hash != $expected_hash {
                log_error "Scoop installer hash verification failed"
                return false
            }
            let result = if $elevated {
                (^powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp_script -RunAsAdmin | complete)
            } else {
                (^powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp_script | complete)
            }
            if $result.exit_code != 0 {
                log_error "Scoop install failed"
                return false
            }
            let scoop_root = ($env.SCOOP? | default ($env.USERPROFILE | path join "scoop"))
            let scoop_shims = ($scoop_root | path join "shims")
            let scoop_command = ($scoop_shims | path join "scoop.cmd")
            if ($scoop_command | path exists) {
                $env.SCOOP = $scoop_root
                $env.PATH = ($env.PATH | prepend $scoop_shims)
            }
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
        } finally {
            rm --force $temp_script
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
        let script = '& { param([string]$Path) $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue; if ($null -ne $item) { $item.Target } }'
        try {
            ^powershell -NoProfile -Command $script $path | str trim
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

    def initialize_transaction_journal [path: string]: nothing -> bool {
        let script = '& { param([string]$Path) $ErrorActionPreference = "Stop"; $directory = Split-Path -Parent $Path; $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User; $directoryAcl = New-Object Security.AccessControl.DirectorySecurity; $directoryAcl.SetAccessRuleProtection($true, $false); $directoryAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"))); [IO.Directory]::CreateDirectory($directory) | Out-Null; [IO.Directory]::SetAccessControl($directory, $directoryAcl); $fileAcl = New-Object Security.AccessControl.FileSecurity; $fileAcl.SetAccessRuleProtection($true, $false); $fileAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "Allow"))); [IO.File]::WriteAllText($Path, ""); [IO.File]::SetAccessControl($Path, $fileAcl) }'
        try {
            let result = (^powershell -NoProfile -Command $script $path | complete)
            $result.exit_code == 0
        } catch {
            false
        }
    }

    def append_transaction_journal [path: string, entry: record, durable: bool = false]: nothing -> bool {
        let line = (($entry | to json -r) + "\n")
        let encoded_line = ($line | encode base64)
        let script = '& { param([string]$Path, [string]$EncodedLine, [string]$Durable) $ErrorActionPreference = "Stop"; $bytes = [Convert]::FromBase64String($EncodedLine); $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::Read); try { $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null; $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($Durable -eq "true") } finally { $stream.Dispose() } }'
        try {
            let result = (^powershell -NoProfile -Command $script $path $encoded_line $durable | complete)
            $result.exit_code == 0
        } catch {
            false
        }
    }

    def link_config [source: string, dest: string, is_file: bool, name: string, stage: string, rollback: string, dry: bool]: nothing -> record {
        if not ($source | path exists) {
            log_error $"Source not found: ($name)"
            return {ok: false, had_live: false}
        }
        if $dry {
            log_dry $"Would link: ($name) -> ($dest)"
            return {ok: true, had_live: false}
        }
        let script = '& { param([string]$Source, [string]$Dest, [string]$IsFile, [string]$Stage, [string]$Rollback) $ErrorActionPreference = "Stop"; function Get-Entry([string]$Path) { Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }; function Get-PathIdentity($Item) { $target = if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [string]::Join([char]31, @($Item.Target | ForEach-Object { $_.ToString() })) } else { "" }; $length = if ($Item.PSIsContainer) { -1 } else { [int64]$Item.Length }; @{ creation_time_utc_ticks = $Item.CreationTimeUtc.Ticks; last_write_time_utc_ticks = $Item.LastWriteTimeUtc.Ticks; attributes = [int64]$Item.Attributes; target = $target; length = $length } }; function Test-PathIdentity($Item, $Identity) { if ($null -eq $Item -or $null -eq $Identity) { return $false }; $actual = Get-PathIdentity $Item; return $actual.creation_time_utc_ticks -eq $Identity.creation_time_utc_ticks -and $actual.last_write_time_utc_ticks -eq $Identity.last_write_time_utc_ticks -and $actual.attributes -eq $Identity.attributes -and $actual.target -eq $Identity.target -and $actual.length -eq $Identity.length }; function Remove-Link([string]$Path) { $item = Get-Entry $Path; if ($null -eq $item) { return }; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw "Refusing to remove a non-link path: $Path" }; if ($item.PSIsContainer) { [IO.Directory]::Delete($Path) } else { [IO.File]::Delete($Path) } }; function Test-Link([string]$Path, [string]$Target) { $item = Get-Entry $Path; if ($null -eq $item -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) { return $false }; $expected = [IO.Path]::GetFullPath($Target).TrimEnd("\\"); return (@($item.Target) | Where-Object { [IO.Path]::GetFullPath($_.ToString()).TrimEnd("\\") -eq $expected } | Measure-Object).Count -gt 0 }; $live = Get-Entry $Dest; $hadLive = $null -ne $live; $rollbackIdentity = if ($hadLive) { Get-PathIdentity $live } else { $null }; try { if ($null -ne (Get-Entry $Stage)) { throw "Staging path already exists: $Stage" }; if ($null -ne (Get-Entry $Rollback)) { throw "Rollback path already exists: $Rollback" }; [IO.Directory]::CreateDirectory((Split-Path -Parent $Dest)) | Out-Null; try { New-Item -ItemType SymbolicLink -Path $Stage -Target $Source -ErrorAction Stop | Out-Null } catch { if ($IsFile -eq "true") { throw }; New-Item -ItemType Junction -Path $Stage -Target $Source -ErrorAction Stop | Out-Null }; if (-not (Test-Link $Stage $Source)) { throw "Staged link verification failed: $Stage" }; try { if ($hadLive) { Move-Item -LiteralPath $Dest -Destination $Rollback -ErrorAction Stop; if (-not (Test-PathIdentity (Get-Entry $Rollback) $rollbackIdentity)) { throw "Rollback identity changed after move: $Rollback" } }; Move-Item -LiteralPath $Stage -Destination $Dest -ErrorAction Stop; if (-not (Test-Link $Dest $Source)) { throw "Live link verification failed: $Dest" } } catch { Remove-Link $Dest; if ($hadLive -and (Test-PathIdentity (Get-Entry $Rollback) $rollbackIdentity)) { Move-Item -LiteralPath $Rollback -Destination $Dest -ErrorAction Stop }; throw }; $created = Get-Entry $Dest; $identityTarget = [IO.Path]::GetFullPath((@($created.Target)[0]).ToString()).TrimEnd("\\"); @{ ok = $true; had_live = $hadLive; identity = @{ creation_time_utc_ticks = $created.CreationTimeUtc.Ticks; attributes = [int64]$created.Attributes; target = $identityTarget }; rollback_identity = $rollbackIdentity } | ConvertTo-Json -Compress -Depth 4 } catch { try { Remove-Link $Stage } catch {}; @{ ok = $false; had_live = $hadLive; error = $_.Exception.Message } | ConvertTo-Json -Compress; exit 1 } }'
        try {
            let ps = (powershell_host)
            let result = (^$ps -NoProfile -Command $script $source $dest $is_file $stage $rollback | complete)
            let response = ($result.stdout | str trim | from json)
            if $result.exit_code == 0 and $response.ok {
                log_info $"Linked: ($name) -> ($dest)"
                return $response
            }
            let detail = ($response.error? | default "unknown error")
            log_error $"Failed to link: ($name): ($detail)"
            return {ok: false, had_live: ($response.had_live? | default false)}
        } catch {
            log_error $"Failed to link: ($name)"
            {ok: false, had_live: false}
        }
    }

    def rollback_link_config [source: string, dest: string, rollback: string, had_live: bool, identity: record, rollback_identity: any]: nothing -> bool {
        let encoded_identity = ($identity | to json -r | encode base64)
        let encoded_rollback_identity = ($rollback_identity | to json -r | encode base64)
        let script = '& { param([string]$Source, [string]$Dest, [string]$Rollback, [string]$HadLive, [string]$EncodedIdentity, [string]$EncodedRollbackIdentity) $ErrorActionPreference = "Stop"; $identity = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedIdentity)) | ConvertFrom-Json; $rollbackIdentity = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedRollbackIdentity)) | ConvertFrom-Json; function Get-Entry([string]$Path) { Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }; function Normalize-Target([string]$Target) { [IO.Path]::GetFullPath($Target).TrimEnd("\\") }; function Test-Link([string]$Path, [string]$Target) { $item = Get-Entry $Path; if ($null -eq $item -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) { return $false }; $expected = Normalize-Target $Target; return (@($item.Target) | Where-Object { (Normalize-Target $_.ToString()) -eq $expected } | Measure-Object).Count -gt 0 }; function Test-RollbackIdentity($Item) { if ($null -eq $Item) { return $false }; $target = if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [string]::Join([char]31, @($Item.Target | ForEach-Object { $_.ToString() })) } else { "" }; $length = if ($Item.PSIsContainer) { -1 } else { [int64]$Item.Length }; return $Item.CreationTimeUtc.Ticks -eq $rollbackIdentity.creation_time_utc_ticks -and $Item.LastWriteTimeUtc.Ticks -eq $rollbackIdentity.last_write_time_utc_ticks -and [int64]$Item.Attributes -eq $rollbackIdentity.attributes -and $target -eq $rollbackIdentity.target -and $length -eq $rollbackIdentity.length }; function Remove-Link([string]$Path) { $item = Get-Entry $Path; if ($item.PSIsContainer) { [IO.Directory]::Delete($Path) } else { [IO.File]::Delete($Path) } }; try { if ($HadLive -eq "true" -and -not (Test-RollbackIdentity (Get-Entry $Rollback))) { throw "Rollback identity does not match the original destination: $Rollback" }; $destItem = Get-Entry $Dest; if ($null -ne $destItem) { if (-not (Test-Link $Dest $Source)) { throw "Destination source does not match the transaction-created link: $Dest" }; $actualTarget = Normalize-Target (@($destItem.Target)[0]).ToString(); if ($actualTarget -ne (Normalize-Target $identity.target) -or $destItem.CreationTimeUtc.Ticks -ne $identity.creation_time_utc_ticks -or [int64]$destItem.Attributes -ne $identity.attributes) { throw "Destination identity does not match the transaction-created link: $Dest" }; Remove-Link $Dest }; if ($HadLive -eq "true") { Move-Item -LiteralPath $Rollback -Destination $Dest -ErrorAction Stop }; exit 0 } catch { exit 1 } }'
        try {
            let result = (^powershell -NoProfile -Command $script $source $dest $rollback $had_live $encoded_identity $encoded_rollback_identity | complete)
            $result.exit_code == 0
        } catch {
            false
        }
    }

    def rollback_link_targets [linked_targets: list<any>, journal: string]: nothing -> bool {
        mut rollback_ok = true
        for linked in ($linked_targets | reverse) {
            if (rollback_link_config $linked.source $linked.dest $linked.rollback $linked.had_live $linked.identity $linked.rollback_identity) {
                if not (append_transaction_journal $journal {
                    event: "target_rolled_back"
                    timestamp: (date now | format date "%+")
                    name: $linked.name
                    source: $linked.source
                    dest: $linked.dest
                    identity: $linked.identity
                    rollback_identity: $linked.rollback_identity
                }) {
                    log_warn $"Failed to journal rollback: ($linked.name)"
                }
            } else {
                $rollback_ok = false
                let _ = (append_transaction_journal $journal {
                    event: "rollback_failed"
                    timestamp: (date now | format date "%+")
                    name: $linked.name
                    source: $linked.source
                    dest: $linked.dest
                    rollback: $linked.rollback
                    identity: $linked.identity
                    rollback_identity: $linked.rollback_identity
                })
                log_error $"Rollback failed: ($linked.name)"
            }
        }
        $rollback_ok
    }

    def fail_link_transaction [linked_targets: list<any>, journal: string, target: record, message: string] {
        let _ = (append_transaction_journal $journal {
            event: "target_failed"
            timestamp: (date now | format date "%+")
            name: $target.name
            source: $target.source
            dest: $target.dest
        })
        let rollback_ok = (rollback_link_targets $linked_targets $journal)
        let _ = (append_transaction_journal $journal {
            event: "run_failed"
            timestamp: (date now | format date "%+")
            failed_target: $target.name
            rollback_ok: $rollback_ok
        })
        error make {msg: $message}
    }

    def remove_rollback_path [path: string, identity: record]: nothing -> bool {
        let encoded_identity = ($identity | to json -r | encode base64)
        let script = '& { param([string]$Path, [string]$EncodedIdentity) $ErrorActionPreference = "Stop"; $identity = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedIdentity)) | ConvertFrom-Json; $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue; if ($null -eq $item) { exit 1 }; $actualTarget = if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [string]::Join([char]31, @($item.Target | ForEach-Object { $_.ToString() })) } else { "" }; $actualLength = if ($item.PSIsContainer) { -1 } else { [int64]$item.Length }; if ($item.CreationTimeUtc.Ticks -ne $identity.creation_time_utc_ticks -or $item.LastWriteTimeUtc.Ticks -ne $identity.last_write_time_utc_ticks -or [int64]$item.Attributes -ne $identity.attributes -or $actualTarget -ne $identity.target -or $actualLength -ne $identity.length) { exit 1 }; Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }'
        try {
            let result = (^powershell -NoProfile -Command $script $path $encoded_identity | complete)
            $result.exit_code == 0
        } catch {
            false
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

    def ensure_real_dir [dest: string, name: string, dry: bool]: nothing -> bool {
        if $dry {
            log_dry $"Would ensure directory: ($name) -> ($dest)"
            return true
        }

        let link_target = (read_link_target $dest)

        if (($link_target | str length) > 0) {
            log_error $"($name): existing link blocks required real directory: ($dest)"
            return false
        }
        if ($dest | path exists) and (($dest | path type) != "dir") {
            log_error $"($name): non-directory path blocks required real directory: ($dest)"
            return false
        }

        if not ($dest | path exists) {
            try {
                mkdir $dest
            } catch {
                log_error $"($name): failed to create directory: ($dest)"
                return false
            }
        }
        true
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

        if not (ensure_scoop $dry_run $is_admin) {
            log_error "Scoop required"
            error make "Scoop required"
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
            dest: ($user_config_home | path join "wezterm" | path join "wezterm.lua")
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

    let codex_config = ($ai_root | path join ".codex" | path join "config.toml")
    let codex_windows_config = ($ai_root | path join ".codex" | path join "windows.config.toml")
    let codex_linux_config = ($ai_root | path join ".codex" | path join "linux.config.toml")
    let codex_hooks = ($ai_root | path join ".codex" | path join "hooks.json")
    let codex_agents = ($ai_root | path join ".codex" | path join "agents")
    if $should_link_codex {
        let codex_files = [
            {src: $shared_agents,       dest: ($codex_home | path join "AGENTS.md"),            is_file: true,  name: "Codex AGENTS.md"}
            {src: $codex_config,         dest: ($codex_home | path join "config.toml"),          is_file: true,  name: "Codex config"}
            {src: $codex_windows_config, dest: ($codex_home | path join "windows.config.toml"), is_file: true,  name: "Codex Windows profile"}
            {src: $codex_linux_config,  dest: ($codex_home | path join "linux.config.toml"),     is_file: true,  name: "Codex Linux profile"}
            {src: $codex_hooks,         dest: ($codex_home | path join "hooks.json"),             is_file: true,  name: "Codex hooks"}
            {src: $codex_agents,        dest: ($codex_home | path join "agents"),                is_file: false, name: "Codex agents"}
            {src: $shared_skills,       dest: ($codex_home | path join "skills"),                is_file: false, name: "Codex skills"}
        ]
        $targets ++= (existing_targets $codex_files)
    }

    if $should_link_grok {
        let grok_files = [
            {src: $shared_agents, dest: ($grok_home | path join "AGENTS.md"), is_file: true, name: "Grok AGENTS.md"}
            {src: ($ai_root | path join ".grok" | path join "config.toml"), dest: ($grok_home | path join "config.toml"), is_file: true, name: "Grok config.toml"}
        ]
        $targets ++= (existing_targets $grok_files)
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
        if not (ensure_real_dir $claude_skills_dest ".claude skills" $dry_run) {
            error make {msg: "Failed to ensure .claude skills directory"}
        }
    }
    if (should_install "yasb" $skip_list $only_list) {
        if not (ensure_real_dir $yasb_config_dir "Yasb config dir" $dry_run) {
            error make {msg: "Failed to ensure Yasb config directory"}
        }
    }

    let transaction_id = (random uuid | into string)
    let transaction_root = ($localappdata | path join "envCross_dotfiles" | path join "transactions")
    let transaction_journal = ($transaction_root | path join $"($transaction_id).jsonl")
    mut linked_targets = []

    if not $dry_run {
        if not (initialize_transaction_journal $transaction_journal) {
            error make {msg: "Failed to create restricted transaction journal"}
        }
        if not (append_transaction_journal $transaction_journal {
            event: "run_started"
            transaction_id: $transaction_id
            timestamp: (date now | format date "%+")
        }) {
            error make {msg: "Failed to initialize transaction journal"}
        }
    }

    for t in $targets {
        let sibling_root = ($t.dest | path dirname)
        let sibling_name = ($t.dest | path basename)
        let stage = ($sibling_root | path join $".($sibling_name).envCross-($transaction_id).stage")
        let rollback = ($sibling_root | path join $".($sibling_name).envCross-($transaction_id).rollback")

        if not $dry_run and not (append_transaction_journal $transaction_journal {
            event: "target_planned"
            timestamp: (date now | format date "%+")
            name: $t.name
            source: $t.source
            dest: $t.dest
            stage: $stage
            rollback: $rollback
        }) {
            fail_link_transaction $linked_targets $transaction_journal $t $"Failed to journal planned target: ($t.name)"
        }

        let link_result = (link_config $t.source $t.dest $t.is_file $t.name $stage $rollback $dry_run)
        if not $link_result.ok {
            if $dry_run {
                error make {msg: $"Link transaction failed: ($t.name)"}
            }
            fail_link_transaction $linked_targets $transaction_journal $t $"Link transaction failed: ($t.name)"
        }

        if not $dry_run {
            $linked_targets ++= [{
                name: $t.name
                source: $t.source
                dest: $t.dest
                rollback: $rollback
                had_live: $link_result.had_live
                identity: $link_result.identity
                rollback_identity: $link_result.rollback_identity
            }]
            if not (append_transaction_journal $transaction_journal {
                event: "target_swapped"
                timestamp: (date now | format date "%+")
                name: $t.name
                source: $t.source
                dest: $t.dest
                rollback: $rollback
                had_live: $link_result.had_live
                identity: $link_result.identity
                rollback_identity: $link_result.rollback_identity
            }) {
                fail_link_transaction $linked_targets $transaction_journal $t $"Failed to journal swapped target: ($t.name)"
            }
        }
    }

    if not $dry_run {
        if not (append_transaction_journal $transaction_journal {
            event: "run_committed"
            transaction_id: $transaction_id
            timestamp: (date now | format date "%+")
            target_count: ($linked_targets | length)
        } true) {
            let rollback_ok = (rollback_link_targets $linked_targets $transaction_journal)
            let _ = (append_transaction_journal $transaction_journal {
                event: "run_failed"
                timestamp: (date now | format date "%+")
                failed_target: "run_commit"
                rollback_ok: $rollback_ok
            })
            error make {msg: "Failed to persist transaction commit point"}
        }

        for linked in $linked_targets {
            if $linked.had_live {
                if (remove_rollback_path $linked.rollback $linked.rollback_identity) {
                    if not (append_transaction_journal $transaction_journal {
                        event: "rollback_removed"
                        timestamp: (date now | format date "%+")
                        name: $linked.name
                        rollback: $linked.rollback
                        rollback_identity: $linked.rollback_identity
                    }) {
                        log_warn $"Failed to journal rollback cleanup: ($linked.name)"
                    }
                } else {
                    let warning_recorded = (append_transaction_journal $transaction_journal {
                        event: "rollback_cleanup_failed"
                        timestamp: (date now | format date "%+")
                        name: $linked.name
                        rollback: $linked.rollback
                        rollback_identity: $linked.rollback_identity
                    })
                    log_warn $"Committed transaction retained rollback artifact: ($linked.rollback)"
                    if not $warning_recorded {
                        log_warn $"Failed to journal rollback cleanup warning: ($linked.name)"
                    }
                }
            }
        }
        if not (append_transaction_journal $transaction_journal {
            event: "run_completed"
            transaction_id: $transaction_id
            timestamp: (date now | format date "%+")
        }) {
            log_warn $"Committed transaction status update failed: ($transaction_journal)"
        }
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
