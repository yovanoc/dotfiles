# macOS-only. Keep in sync with os/linux.zsh.

# Type a filename to open it
alias -s html=open

# Global alias: pipe anything to the clipboard
alias -g C='| pbcopy'

# Copy the current command line to the clipboard (Ctrl+X Ctrl+C)
function copy-buffer-to-clipboard() {
    print -rn -- "$BUFFER" | pbcopy
    zle -M "Copied to clipboard"
}
zle -N copy-buffer-to-clipboard
bindkey '^X^C' copy-buffer-to-clipboard

# Cleanup chain (brew-only, hence macOS-only)
alias brew-clean='brew cleanup --prune=all && brew autoremove'
alias soft-clean='dk-clean && brew-clean'
alias clean='soft-clean && rmall'

# terraform completion (homebrew path). Works because .zshrc runs compinit eagerly.
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

# Keep the Mac awake (display included). Toggle, or `awake on|off`, or `awake 4` for 4h.
# launchd owns caffeinate (no controlling tty), so closing the terminal can't kill it.
function awake() {
    local hours=""
    [[ $1 == <-> ]] && hours=$1
    local running=$(pgrep -x caffeinate)
    launchctl remove awake 2>/dev/null
    pkill -x caffeinate 2>/dev/null
    if [[ $1 == off || ( -z $1 && -n $running ) ]]; then
        echo "awake: off"
        return
    fi
    launchctl submit -l awake -- caffeinate -d ${hours:+-t $(( hours * 3600 ))}
    echo "awake: on${hours:+ for ${hours}h}"
}
