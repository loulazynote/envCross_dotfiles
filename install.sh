#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR=""
TRANSACTION_ROOT=""
TRANSACTION_DIR=""
TRANSACTION_JOURNAL=""
TRANSACTION_ID=""
TRANSACTION_ACTIVE=false
TRANSACTION_ROLLING_BACK=false
TRANSACTION_INDEX=0

# Options
DRY_RUN=false
NO_BACKUP=false
NO_INSTALL=false
FORCE_INSTALL=false
BACKUP_ONLY=false
SKIP_TOOLS=()
ONLY_TOOLS=()

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

source "$REPO_ROOT/scripts/lib/targets.sh"
load_install_targets


log_info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
log_step()  { printf "${BLUE}[STEP]${NC}  %s\n" "$1"; }
log_dry()   { printf "${YELLOW}[DRY]${NC}   %s\n" "$1"; }

die() { log_error "$1"; exit 1; }


show_help() {
    cat << EOF
Usage: ./install.sh [OPTIONS]

Options:
  -n, --dry-run       Show what would be done without making changes
  -b, --backup        Backup existing configs only (no install/link)
  --no-backup         Skip backup step
  --no-install        Skip package installation
  --force-install     Force reinstall packages
  --skip-<tool>       Skip specific tool (e.g., --skip-ghostty)
  --only-<tool>       Only install specific tool (e.g., --only-neovim)
  -h, --help          Show this help

Examples:
  ./install.sh                        # Full installation
  ./install.sh --dry-run              # Preview changes
  ./install.sh --backup               # Backup only
  ./install.sh --skip-kitty           # Skip kitty
  ./install.sh --only-neovim          # Only install neovim

Tools:
  Core:   $(join_targets_by_group core)
  AI:     $(join_targets_by_group ai)
  Niri:   $(join_targets_by_group niri)
  Utils:  $(join_targets_by_group utilities)
  Config: $(join_targets_by_group config)
EOF
    exit 0
}


parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)      DRY_RUN=true ;;
            -b|--backup)       BACKUP_ONLY=true ;;
            --no-backup)       NO_BACKUP=true ;;
            --no-install)      NO_INSTALL=true ;;
            --force-install)   FORCE_INSTALL=true ;;
            --skip-*)          SKIP_TOOLS+=("${1#--skip-}") ;;
            --only-*)          ONLY_TOOLS+=("${1#--only-}") ;;
            -h|--help)         show_help ;;
            *)                 log_warn "Unknown option: $1" ;;
        esac
        shift
    done
}


AUR_HELPER=""

detect_system() {
    command -v pacman &>/dev/null || die "pacman not found - Arch-based distro required"

    # Prefer paru over yay
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    else
        log_warn "No AUR helper found (paru/yay). AUR packages will be skipped, official packages will use pacman."
    fi
}


should_process() {
    local name="$1"

    if [[ ${#ONLY_TOOLS[@]} -gt 0 ]]; then
        for only in "${ONLY_TOOLS[@]}"; do
            [[ "$name" == "$only" ]] && return 0
        done
        return 1
    fi

    for skip in "${SKIP_TOOLS[@]}"; do
        [[ "$name" == "$skip" ]] && return 1
    done

    return 0
}


is_installed() {
    local cmd="$1"

    if [[ "$cmd" == /* ]]; then
        [[ -f "$cmd" ]]
    else
        command -v "$cmd" &>/dev/null
    fi
}

install_packages() {
    local pkgs="$1"
    local is_aur="$2"

    # Split comma-separated packages
    IFS=',' read -ra pkg_array <<< "$pkgs"

    if [[ "$is_aur" == "true" ]]; then
        if [[ -z "$AUR_HELPER" ]]; then
            log_warn "No AUR helper available, skipping: ${pkg_array[*]}"
            return 1
        fi
        $AUR_HELPER -S --noconfirm --needed "${pkg_array[@]}"
    else
        if [[ -n "$AUR_HELPER" ]]; then
            $AUR_HELPER -S --noconfirm --needed "${pkg_array[@]}"
        else
            sudo pacman -S --noconfirm --needed "${pkg_array[@]}"
        fi
    fi
}

install_tool() {
    local name="$1"
    local cmd="$2"
    local pkg="$3"
    local is_aur="$4"

    if is_installed "$cmd"; then
        if [[ "$FORCE_INSTALL" == "false" ]]; then
            log_info "$name: already installed"
            return 0
        fi
        log_info "$name: reinstalling (--force-install)"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would install: $name ($pkg)"
        return 0
    fi

    log_info "Installing $name..."
    if install_packages "$pkg" "$is_aur"; then
        if is_installed "$cmd"; then
            log_info "$name: installed successfully"
        else
            log_warn "$name: package installed but command not found"
        fi
    else
        log_warn "$name: installation failed"
        return 1
    fi
}

ensure_stow() {
    if command -v stow &>/dev/null; then
        log_info "stow: already installed"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would install required tool: stow"
        return 0
    fi

    if [[ "$NO_INSTALL" == "true" ]]; then
        log_warn "stow is required; installing even with --no-install"
    fi

    log_info "stow: not found, installing..."
    if install_packages "stow" "false" && command -v stow &>/dev/null; then
        log_info "stow: installed successfully"
        return 0
    fi

    die "failed to install required tool: stow"
}


init_backup_dir() {
    if [[ "$NO_BACKUP" == "true" ]]; then
        return
    fi

    BACKUP_DIR="$REPO_ROOT/backup/$(date +%Y%m%d-%H%M%S)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Backup directory: $BACKUP_DIR"
    else
        mkdir -p "$BACKUP_DIR"
        log_info "Backup directory: $BACKUP_DIR"
    fi
}

path_in_repo() {
    local path="$1"

    [[ "$path" == "$REPO_ROOT" || "$path" == "$REPO_ROOT/"* ]]
}

path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

is_windows_posix() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

validate_transaction_field() {
    local label="$1"
    local value="$2"
    local LC_ALL=C

    if [[ -z "$value" || "$value" =~ [[:cntrl:]] ]]; then
        log_error "transaction: invalid $label"
        return 1
    fi
}

link_points_to() {
    local path="$1"
    local expected_source="$2"

    if [[ "$(readlink "$path" 2>/dev/null || true)" == "$expected_source" && -e "$path" ]]; then
        return 0
    fi

    is_windows_posix && [[ -f "$path" && -f "$expected_source" ]] && cmp -s -- "$path" "$expected_source"
}

path_identity() {
    stat -c '%d:%i' -- "$1"
}

set_private_permissions() {
    if chmod "$1" "$2" 2>/dev/null; then
        return 0
    fi

    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

sync_journal() {
    if sync "$TRANSACTION_JOURNAL" 2>/dev/null; then
        return 0
    fi

    is_windows_posix
}

transaction_directory_is_owned() {
    [[ "$(stat -c '%u' -- "$1" 2>/dev/null || true)" == "$(id -u)" ]]
}

verify_transaction_directory() {
    local path="$1"

    [[ ! -L "$path" && -d "$path" ]] || return 1
    transaction_directory_is_owned "$path" || return 1
    is_windows_posix || [[ "$(stat -c '%a' -- "$path" 2>/dev/null || true)" == "700" ]]
}

init_transaction() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    [[ "$TRANSACTION_ACTIVE" == "true" ]] && return 0

    TRANSACTION_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/envcross/transactions"
    validate_transaction_field "transaction root" "$TRANSACTION_ROOT"
    if path_exists "$TRANSACTION_ROOT"; then
        if [[ -L "$TRANSACTION_ROOT" || ! -d "$TRANSACTION_ROOT" ]]; then
            log_error "transaction: root must be a directory and not a symlink"
            return 1
        fi
        if ! transaction_directory_is_owned "$TRANSACTION_ROOT"; then
            log_error "transaction: root must be owned by the current user"
            return 1
        fi
    fi
    (umask 077; mkdir -p "$TRANSACTION_ROOT")
    if ! verify_transaction_directory "$TRANSACTION_ROOT"; then
        log_error "transaction: root must remain owner-only mode 700"
        return 1
    fi

    TRANSACTION_DIR="$(umask 077; mktemp -d "$TRANSACTION_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")"
    if ! verify_transaction_directory "$TRANSACTION_DIR"; then
        log_error "transaction: directory must remain owner-only mode 700"
        return 1
    fi
    TRANSACTION_JOURNAL="$TRANSACTION_DIR/journal"
    TRANSACTION_ID="$(basename "$TRANSACTION_DIR")"
    (umask 077; : > "$TRANSACTION_JOURNAL")
    set_private_permissions 600 "$TRANSACTION_JOURNAL"
    printf 'state\tactive\n' >> "$TRANSACTION_JOURNAL"
    sync_journal
    TRANSACTION_ACTIVE=true
}

transaction_log_swap() {
    local swap_kind="$1"
    local dst="$2"
    local rollback="$3"
    local had_destination="$4"
    local expected_source="$5"
    local expected_identity="$6"
    local rollback_identity="$7"

    validate_transaction_field "swap kind" "$swap_kind"
    validate_transaction_field "destination" "$dst"
    validate_transaction_field "rollback path" "$rollback"
    validate_transaction_field "destination state" "$had_destination"
    validate_transaction_field "expected source" "$expected_source"
    validate_transaction_field "expected identity" "$expected_identity"
    validate_transaction_field "rollback identity" "$rollback_identity"
    printf 'swap\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$swap_kind" "$dst" "$rollback" "$had_destination" \
        "$expected_source" "$expected_identity" "$rollback_identity" >> "$TRANSACTION_JOURNAL"
    sync_journal
}

create_staged_link() {
    local src="$1"
    local stage_dir="$2"
    local stage="$stage_dir/link"

    mkdir "$stage_dir"
    if ! set_private_permissions 700 "$stage_dir"; then
        rmdir "$stage_dir" 2>/dev/null || true
        return 1
    fi
    if ! ln -s "$src" "$stage"; then
        rmdir "$stage_dir" 2>/dev/null || true
        return 1
    fi

    if ! link_points_to "$stage" "$src"; then
        rm -f "$stage"
        rmdir "$stage_dir" 2>/dev/null || true
        return 1
    fi
}

cleanup_staged_path() {
    local swap_kind="$1"
    local staged="$2"
    local stage_container="$3"

    if [[ "$swap_kind" == "link" ]]; then
        rm -f -- "$staged" 2>/dev/null || true
        rmdir "$stage_container" 2>/dev/null || true
    else
        rm -rf -- "$staged" 2>/dev/null || true
    fi
}

destination_matches_transaction() {
    local swap_kind="$1"
    local dst="$2"
    local expected_source="$3"
    local expected_identity="$4"
    local current_identity

    current_identity="$(path_identity "$dst" 2>/dev/null || true)"
    [[ "$current_identity" == "$expected_identity" ]] || return 1

    if [[ "$swap_kind" == "link" ]]; then
        link_points_to "$dst" "$expected_source"
    else
        [[ -d "$dst" && ! -L "$dst" ]]
    fi
}

activate_staged_path() {
    local swap_kind="$1"
    local staged="$2"
    local stage_container="$3"
    local dst="$4"
    local expected_source="$5"
    local name="$6"
    local rollback="-" had_destination=false
    local expected_identity rollback_identity="-"

    expected_identity="$(path_identity "$staged")" || {
        cleanup_staged_path "$swap_kind" "$staged" "$stage_container"
        return 1
    }

    if path_exists "$dst"; then
        had_destination=true
        rollback="$dst.envcross-rollback-${TRANSACTION_ID}-${TRANSACTION_INDEX}"
        if path_exists "$rollback"; then
            cleanup_staged_path "$swap_kind" "$staged" "$stage_container"
            log_error "$name: rollback sibling already exists ($rollback)"
            return 1
        fi
        rollback_identity="$(path_identity "$dst")" || {
            cleanup_staged_path "$swap_kind" "$staged" "$stage_container"
            return 1
        }
    fi

    if ! transaction_log_swap "$swap_kind" "$dst" "$rollback" "$had_destination" \
        "$expected_source" "$expected_identity" "$rollback_identity"; then
        cleanup_staged_path "$swap_kind" "$staged" "$stage_container"
        log_error "$name: failed to journal replacement"
        return 1
    fi

    if [[ "$had_destination" == "true" ]] && ! mv -- "$dst" "$rollback"; then
        cleanup_staged_path "$swap_kind" "$staged" "$stage_container"
        log_error "$name: failed to preserve existing destination"
        return 1
    fi

    if ! mv -- "$staged" "$dst"; then
        cleanup_staged_path "$swap_kind" "$staged" "$stage_container"
        log_error "$name: failed to activate staged destination"
        return 1
    fi

    if [[ "$swap_kind" == "link" ]]; then
        rmdir "$stage_container" 2>/dev/null || true
    fi

    if ! destination_matches_transaction "$swap_kind" "$dst" "$expected_source" "$expected_identity"; then
        log_error "$name: activated destination verification failed"
        return 1
    fi

    if [[ "$swap_kind" == "link" ]]; then
        log_info "$name: linked -> $dst"
    else
        log_info "$name: stowed -> $dst"
    fi
}

replace_link_transactionally() {
    local src="$1"
    local dst="$2"
    local name="$3"
    local parent stage_dir stage

    validate_transaction_field "source" "$src"
    validate_transaction_field "destination" "$dst"
    validate_transaction_field "name" "$name"
    init_transaction
    parent="$(dirname "$dst")"
    mkdir -p "$parent"
    TRANSACTION_INDEX=$((TRANSACTION_INDEX + 1))
    stage_dir="$parent/.envcross-stage-${TRANSACTION_ID}-${TRANSACTION_INDEX}"
    stage="$stage_dir/link"
    create_staged_link "$src" "$stage_dir"
    activate_staged_path "link" "$stage" "$stage_dir" "$dst" "$src" "$name"
}

rollback_transaction() {
    [[ "$TRANSACTION_ACTIVE" == "true" ]] || return 0

    local record_kind swap_kind dst rollback had_destination expected_source expected_identity rollback_identity
    local current_rollback_identity
    local -a swap_kinds=() destinations=() rollbacks=() had_destinations=()
    local -a expected_sources=() expected_identities=() rollback_identities=()
    local result=0 index

    while IFS=$'\t' read -r record_kind swap_kind dst rollback had_destination expected_source expected_identity rollback_identity; do
        [[ "$record_kind" == "swap" ]] || continue
        swap_kinds+=("$swap_kind")
        destinations+=("$dst")
        rollbacks+=("$rollback")
        had_destinations+=("$had_destination")
        expected_sources+=("$expected_source")
        expected_identities+=("$expected_identity")
        rollback_identities+=("$rollback_identity")
    done < "$TRANSACTION_JOURNAL"

    for ((index=${#destinations[@]} - 1; index>=0; index--)); do
        swap_kind="${swap_kinds[index]}"
        dst="${destinations[index]}"
        rollback="${rollbacks[index]}"
        had_destination="${had_destinations[index]}"
        expected_source="${expected_sources[index]}"
        expected_identity="${expected_identities[index]}"
        rollback_identity="${rollback_identities[index]}"

        if path_exists "$dst"; then
            if destination_matches_transaction "$swap_kind" "$dst" "$expected_source" "$expected_identity"; then
                if [[ "$swap_kind" == "link" ]]; then
                    rm -f -- "$dst" || result=1
                else
                    rm -rf -- "$dst" || result=1
                fi
            else
                log_error "rollback: destination changed outside this transaction ($dst)"
                result=1
                continue
            fi
        fi

        if [[ "$had_destination" == "true" ]]; then
            if path_exists "$rollback"; then
                current_rollback_identity="$(path_identity "$rollback" 2>/dev/null || true)"
                if [[ "$current_rollback_identity" == "$rollback_identity" ]]; then
                    mv -- "$rollback" "$dst" || result=1
                else
                    log_error "rollback: preserved destination changed ($rollback)"
                    result=1
                fi
            else
                log_error "rollback: preserved destination missing ($rollback)"
                result=1
            fi
        fi
    done

    if [[ "$result" -eq 0 ]]; then
        printf 'state\trolled-back\n' >> "$TRANSACTION_JOURNAL" || result=1
    else
        printf 'state\trollback-failed\n' >> "$TRANSACTION_JOURNAL" || true
    fi
    sync_journal || result=1
    TRANSACTION_ACTIVE=false
    return "$result"
}

commit_transaction() {
    [[ "$TRANSACTION_ACTIVE" == "true" ]] || return 0

    printf 'state\tcommitted\n' >> "$TRANSACTION_JOURNAL"
    sync_journal
    TRANSACTION_ACTIVE=false

    local record_kind swap_kind dst rollback had_destination expected_source expected_identity rollback_identity
    local current_rollback_identity
    while IFS=$'\t' read -r record_kind swap_kind dst rollback had_destination expected_source expected_identity rollback_identity; do
        [[ "$record_kind" == "swap" && "$had_destination" == "true" ]] || continue
        current_rollback_identity="$(path_identity "$rollback" 2>/dev/null || true)"
        if [[ "$current_rollback_identity" != "$rollback_identity" ]]; then
            log_warn "commit: preserved destination changed; keeping $rollback"
        elif ! rm -rf -- "$rollback"; then
            log_warn "commit: failed to remove rollback sibling $rollback"
        fi
    done < "$TRANSACTION_JOURNAL"
}

handle_failure() {
    local status="$1"

    trap - ERR INT TERM
    if [[ "$TRANSACTION_ACTIVE" == "true" && "$TRANSACTION_ROLLING_BACK" == "false" ]]; then
        TRANSACTION_ROLLING_BACK=true
        rollback_transaction || log_error "rollback did not complete cleanly; see $TRANSACTION_JOURNAL"
    fi
    exit "$status"
}

backup_path() {
    local path="$1"
    local name="$2"

    [[ "$NO_BACKUP" == "true" ]] && return 0
    [[ ! -e "$path" ]] && return 0

    if [[ -L "$path" ]]; then
        local target
        target=$(readlink -f "$path" 2>/dev/null || true)
        if path_in_repo "$target"; then
            log_info "$name: already symlinked to repo"
            return 0
        fi
    fi

    local backup_name
    backup_name=$(echo "$name" | tr '/\\:*?"<>| ' '_')

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would backup: $name"
    else
        if cp -a "$path" "$BACKUP_DIR/$backup_name" 2>/dev/null; then
            log_info "$name: backed up"
        else
            log_warn "$name: backup failed"
        fi
    fi
}


remove_stow_candidate_conflicts() {
    local src_dir="$1"
    local candidate_dir="$2"
    local item base target
    local -a items=()

    shopt -s dotglob nullglob
    items=("$src_dir"/*)
    shopt -u dotglob nullglob
    for item in "${items[@]}"; do
        base="$(basename "$item")"
        target="$candidate_dir/$base"
        if [[ -d "$item" && ! -L "$item" ]]; then
            if [[ -d "$target" && ! -L "$target" ]]; then
                remove_stow_candidate_conflicts "$item" "$target"
            elif path_exists "$target"; then
                rm -rf -- "$target"
            fi
        else
            if path_exists "$target"; then
                rm -rf -- "$target"
            fi
        fi
    done
}

link_resolves_to() {
    local path="$1"
    local expected_source="$2"
    local actual expected

    [[ -L "$path" ]] || return 1
    actual="$(readlink -f "$path" 2>/dev/null || true)"
    expected="$(readlink -f "$expected_source" 2>/dev/null || true)"
    [[ -n "$actual" && "$actual" == "$expected" ]]
}

verify_stow_candidate() {
    local src_dir="$1"
    local candidate_dir="$2"
    local item base target
    local -a items=()

    shopt -s dotglob nullglob
    items=("$src_dir"/*)
    shopt -u dotglob nullglob
    for item in "${items[@]}"; do
        base="$(basename "$item")"
        target="$candidate_dir/$base"
        if [[ -d "$item" && ! -L "$item" ]]; then
            [[ -d "$target" && ! -L "$target" ]] || return 1
            verify_stow_candidate "$item" "$target" || return 1
        else
            link_resolves_to "$target" "$item" || return 1
        fi
    done
}

create_stow_package() {
    local src="$1"
    local dst="$2"
    local name="$3"
    local parent stage

    if [[ ! -d "$src" ]]; then
        log_warn "$name: source not found ($src)"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would stow: $name -> $dst"
        return 0
    fi

    validate_transaction_field "stow source" "$src"
    validate_transaction_field "stow destination" "$dst"
    validate_transaction_field "stow name" "$name"
    init_transaction
    parent="$(dirname "$dst")"
    mkdir -p "$parent"
    TRANSACTION_INDEX=$((TRANSACTION_INDEX + 1))
    stage="$parent/.envcross-stage-${TRANSACTION_ID}-${TRANSACTION_INDEX}"
    mkdir "$stage"
    if ! set_private_permissions 700 "$stage"; then
        rm -rf -- "$stage"
        return 1
    fi

    if [[ -d "$dst" ]] && ! cp -a -- "$dst/." "$stage/"; then
        rm -rf -- "$stage"
        log_error "$name: failed to stage existing destination"
        return 1
    fi

    if ! remove_stow_candidate_conflicts "$src" "$stage"; then
        rm -rf -- "$stage"
        log_error "$name: failed to prepare staged destination"
        return 1
    fi

    if ! stow --no-folding -d "$(dirname "$src")" -t "$stage" "$(basename "$src")"; then
        rm -rf -- "$stage"
        log_error "$name: failed to stow"
        return 1
    fi

    if ! verify_stow_candidate "$src" "$stage"; then
        rm -rf -- "$stage"
        log_error "$name: staged stow verification failed"
        return 1
    fi

    activate_staged_path "tree" "$stage" "-" "$dst" "$src" "$name"
}

create_file_link() {
    local src="$1"
    local dst="$2"
    local name="$3"

    if [[ ! -f "$src" ]]; then
        log_warn "$name: source not found ($src)"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would link: $name -> $dst"
        return 0
    fi

    replace_link_transactionally "$src" "$dst" "$name"
}

create_path_link() {
    local src="$1"
    local dst="$2"
    local name="$3"

    if [[ ! -e "$src" ]]; then
        log_warn "$name: source not found ($src)"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would link: $name -> $dst"
        return 0
    fi

    replace_link_transactionally "$src" "$dst" "$name"
}

directory_has_entries() {
    local path="$1"
    [[ -d "$path" ]] || return 1
    [[ -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

create_optional_path_link() {
    local src="$1"
    local dst="$2"
    local name="$3"

    if directory_has_entries "$src"; then
        create_path_link "$src" "$dst" "$name"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would skip optional link: $name"
    else
        log_info "$name: skipped (source empty or missing)"
    fi
}

link_ai_shared_files() {
    local name="$1"
    local shared_agents="$REPO_ROOT/ai-assistants/AGENTS.md"
    local shared_skills="$REPO_ROOT/ai-assistants/SKILLS"

    case "$name" in
        claude-code)
            local claude_root="$REPO_ROOT/ai-assistants/.claude"
            create_file_link "$claude_root/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "claude-rules" || return 1
            create_file_link "$claude_root/settings.json" "$HOME/.claude/settings.json" "claude-settings" || return 1
            create_path_link "$REPO_ROOT/ai-assistants/hooks" "$HOME/.claude/hooks" "claude-hooks" || return 1
            create_path_link "$shared_skills" "$HOME/.claude/skills" "claude-skills" || return 1
            create_file_link "$claude_root/statusline-command.sh" "$HOME/.claude/statusline-command.sh" "claude-statusline" || return 1
            create_optional_path_link "$claude_root/agents" "$HOME/.claude/agents" "claude-agents" || return 1
            create_optional_path_link "$claude_root/rules" "$HOME/.claude/rules" "claude-rules-dir" || return 1
            create_optional_path_link "$claude_root/marketplace" "$HOME/.claude/marketplace" "claude-marketplace" || return 1
            ;;
        codex)
            create_file_link "$shared_agents" "$HOME/.codex/AGENTS.md" "codex-rules" || return 1
            create_file_link "$REPO_ROOT/ai-assistants/.codex/config.toml" "$HOME/.codex/config.toml" "codex-config" || return 1
            create_file_link "$REPO_ROOT/ai-assistants/.codex/windows.config.toml" "$HOME/.codex/windows.config.toml" "codex-windows-profile" || return 1
            create_file_link "$REPO_ROOT/ai-assistants/.codex/linux.config.toml" "$HOME/.codex/linux.config.toml" "codex-linux-profile" || return 1
            create_file_link "$REPO_ROOT/ai-assistants/.codex/hooks.json" "$HOME/.codex/hooks.json" "codex-hooks" || return 1
            create_path_link "$REPO_ROOT/ai-assistants/.codex/agents" "$HOME/.codex/agents" "codex-agents" || return 1
            create_path_link "$shared_skills" "$HOME/.codex/skills" "codex-skills" || return 1
            ;;
        grok)
            create_file_link "$shared_agents" "$HOME/.grok/AGENTS.md" "grok-rules" || return 1
            ;;
        opencode)
            local opencode_root="$REPO_ROOT/ai-assistants/.opencode"
            create_file_link "$shared_agents" "$HOME/.config/opencode/AGENTS.md" "opencode-rules" || return 1
            create_file_link "$opencode_root/opencode.json" "$HOME/.config/opencode/opencode.json" "opencode-config" || return 1
            create_file_link "$opencode_root/oh-my-opencode-slim.json" "$HOME/.config/opencode/oh-my-opencode-slim.json" "opencode-omc-slim" || return 1
            create_file_link "$opencode_root/tui.json" "$HOME/.config/opencode/tui.json" "opencode-tui" || return 1
            create_path_link "$shared_skills" "$HOME/.config/opencode/skills" "opencode-skills" || return 1
            create_path_link "$opencode_root/agents" "$HOME/.config/opencode/agents" "opencode-agents" || return 1
            create_path_link "$opencode_root/commands" "$HOME/.config/opencode/commands" "opencode-commands" || return 1
            create_path_link "$opencode_root/plugins" "$HOME/.config/opencode/plugins" "opencode-plugins" || return 1
            create_file_link "$opencode_root/enforce-shell-policy.sh" "$HOME/.config/opencode/enforce-shell-policy.sh" "opencode-shell-policy" || return 1
            ;;
        hermes-agent)
            local hermes_root="$REPO_ROOT/ai-assistants/.hermes"
            create_file_link "$hermes_root/SOUL.md" "$HOME/.hermes/SOUL.md" "hermes-soul" || return 1
            create_file_link "$hermes_root/config.yaml" "$HOME/.hermes/config.yaml" "hermes-config" || return 1
            create_path_link "$hermes_root/hooks" "$HOME/.hermes/hooks" "hermes-hooks" || return 1
            ;;
    esac
}

ensure_claude_local_plugin() {
    local marketplace_dir="$REPO_ROOT/ai-assistants/.claude/marketplace"
    local marketplace_name="lou-local-ai"
    local plugin_id="common-lsp@$marketplace_name"

    [[ -d "$marketplace_dir" ]] || return 0

    if ! command -v claude &>/dev/null; then
        log_warn "claude: not found, skipping local plugin install"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would ensure Claude marketplace: $marketplace_name"
        log_dry "Would ensure Claude plugin: $plugin_id"
        return 0
    fi

    local marketplaces
    marketplaces="$(claude plugin marketplace list --json 2>/dev/null || printf '[]')"
    if ! jq -e --arg name "$marketplace_name" '.[] | select(.name == $name)' >/dev/null 2>&1 <<< "$marketplaces"; then
        if claude plugin marketplace add "$marketplace_dir" --scope user >/dev/null 2>&1; then
            log_info "claude marketplace: added $marketplace_name"
        else
            log_warn "claude marketplace: failed to add $marketplace_name"
            return 0
        fi
    else
        log_info "claude marketplace: already added ($marketplace_name)"
    fi

    local plugins
    plugins="$(claude plugin list --json 2>/dev/null || printf '[]')"
    if ! jq -e --arg id "$plugin_id" '.[] | select(.id == $id)' >/dev/null 2>&1 <<< "$plugins"; then
        if claude plugin install "$plugin_id" --scope user >/dev/null 2>&1; then
            log_info "claude plugin: installed $plugin_id"
        else
            log_warn "claude plugin: failed to install $plugin_id"
            return 0
        fi
        plugins="$(claude plugin list --json 2>/dev/null || printf '[]')"
    fi

    if jq -e --arg id "$plugin_id" '.[] | select(.id == $id and .enabled == false)' >/dev/null 2>&1 <<< "$plugins"; then
        if claude plugin enable "$plugin_id" --scope user >/dev/null 2>&1; then
            log_info "claude plugin: enabled $plugin_id"
        else
            log_warn "claude plugin: failed to enable $plugin_id"
        fi
    else
        log_info "claude plugin: ready ($plugin_id)"
    fi
}


step_install_tools() {
    [[ "$NO_INSTALL" == "true" ]] && return

    echo ""
    log_step "=== Step 1: Installing Tools ==="
    echo ""

    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r name cmd pkg is_aur src dst <<< "$entry"
        [[ -z "$pkg" ]] && continue

        should_process "$name" || continue
        install_tool "$name" "$cmd" "$pkg" "$is_aur"
    done
}

step_backup_configs() {
    [[ "$NO_BACKUP" == "true" ]] && return

    echo ""
    log_step "=== Step 2: Backing Up Existing Configs ==="
    echo ""

    init_backup_dir

    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r name cmd pkg is_aur src dst <<< "$entry"
        [[ -z "$dst" ]] && continue

        should_process "$name" || continue

        local full_dst
        if [[ "$dst" == /* ]]; then
            full_dst="$dst"
        else
            full_dst="$CONFIG_HOME/$dst"
        fi

        backup_path "$full_dst" "$name"
    done
}

step_symlink_configs() {
    echo ""
    log_step "=== Step 3: Creating Links ==="
    echo ""

    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r name cmd pkg is_aur src dst <<< "$entry"
        [[ -z "$dst" ]] && continue

        should_process "$name" || continue

        local full_dst
        if [[ "$dst" == /* ]]; then
            full_dst="$dst"
        else
            full_dst="$CONFIG_HOME/$dst"
        fi

        if [[ "$name" == "zed" ]]; then
            local generated_zed_settings="${XDG_CACHE_HOME:-$HOME/.cache}/envCross_dotfiles/zed/settings.json"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_dry "Would render: Zed settings -> $generated_zed_settings"
                log_dry "Would link: Zed settings -> $full_dst"
            else
                python3 "$REPO_ROOT/scripts/merge-json.py" \
                    "$REPO_ROOT/zed/settings.json" \
                    "$REPO_ROOT/zed/lsp.linux.json" \
                    "$generated_zed_settings"
                create_file_link "$generated_zed_settings" "$full_dst" "$name"
            fi
        elif [[ -n "$src" ]]; then
            local full_src="$REPO_ROOT/$src"

            if [[ -d "$full_src" ]]; then
                create_stow_package "$full_src" "$full_dst" "$name"
            elif [[ -f "$full_src" ]]; then
                create_file_link "$full_src" "$full_dst" "$name"
            else
                log_warn "$name: source not found ($full_src)"
            fi
        fi

        if [[ "$name" == "yazi" ]]; then
            local yazi_dst="${CONFIG_HOME}/yazi"
            for dir in flavors plugins scripts; do
                local src_dir="$REPO_ROOT/yazi/$dir"
                local dst_dir="$yazi_dst/$dir"
                if [[ -d "$src_dir" ]]; then
                    create_path_link "$src_dir" "$dst_dir" "yazi-$dir"
                fi
            done
        fi

        case "$name" in claude-code|codex|grok|opencode|hermes-agent) link_ai_shared_files "$name" ;; esac
        case "$name" in claude-code) ensure_claude_local_plugin ;; esac
    done

    commit_transaction
}

show_summary() {
    echo ""
    log_step "=== Installation Complete ==="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed. No changes were made."
        return
    fi

    if should_process "fish" && command -v fish &>/dev/null; then
        echo "  Set Fish as default shell: chsh -s \$(which fish)"
    fi

    if should_process "neovim" && command -v nvim &>/dev/null; then
        echo "  Open Neovim to install plugins: nvim"
    fi

    if should_process "awww" && command -v awww &>/dev/null; then
        echo "  Initialize wallpaper daemon: awww-daemon"
    fi

    if should_process "polkit-gnome"; then
        echo "  Add to Niri config: spawn-at-startup \"/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1\""
    fi

    echo ""
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        log_info "Backups saved to: $BACKUP_DIR"
    fi

    echo ""
    echo "Restart your shell: exec \$SHELL"
}


main() {
    echo "============================================"
    echo "  Linux Dotfiles Installer (CachyOS/Arch)"
    echo "============================================"
    echo ""
    echo "Repository: $REPO_ROOT"
    echo "Config:     $CONFIG_HOME"
    echo ""

    parse_args "$@"
    detect_system

    log_info "AUR Helper: ${AUR_HELPER:-none}"
    [[ "$DRY_RUN" == "true" ]] && log_warn "DRY RUN MODE - No changes will be made"

    if [[ "$BACKUP_ONLY" == "true" ]]; then
        step_backup_configs
        [[ -n "$BACKUP_DIR" ]] && log_info "Backup complete: $BACKUP_DIR"
        exit 0
    fi

    ensure_stow

    step_install_tools
    step_backup_configs
    step_symlink_configs
    show_summary
}

trap 'handle_failure "$?"' ERR
trap 'handle_failure 130' INT
trap 'handle_failure 143' TERM

main "$@"
