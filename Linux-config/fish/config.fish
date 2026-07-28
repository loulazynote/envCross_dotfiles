source /usr/share/cachyos-fish-config/cachyos-config.fish

# env
export EDITOR=nvim
export VISUAL=nvim
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"


# paths
# go
fish_add_path (go env GOPATH)/bin
fish_add_path --move --path "$HOME/.local/share/nvim/mason/bin"
# uv (astral)
fish_add_path "/home/lou/.local/bin"
fish_add_path --path "$HOME/.dotnet/tools"
fish_add_path /opt/cuda/bin

set -gx PNPM_HOME "/home/lou/.local/share/pnpm"
fish_add_path --path "$PNPM_HOME"
fish_add_path --path "$PNPM_HOME/bin"

# functions
function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

# init
starship init fish | source
zoxide init fish | source
/home/linuxbrew/.linuxbrew/bin/brew shellenv | source
if type -q direnv
    direnv hook fish | source
end

# google cloud sdk
if [ -f '/home/lou/Documents/Practise/google-cloud-sdk/path.fish.inc' ]; . '/home/lou/Documents/Practise/google-cloud-sdk/path.fish.inc'; end


# >>> grok installer >>>
fish_add_path $HOME/.grok/bin
# <<< grok installer <<<
