alias ytlow  = mpv --profile=low
alias ytmed  = mpv --profile=medium
alias ythigh = mpv --profile=high
alias lg = lazygit

def --wrapped codex [...args] {
    ^codex --profile windows ...$args
}
