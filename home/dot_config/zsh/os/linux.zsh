# Linux-only. Keep in sync with os/macos.zsh.

# Type a filename to open it
alias -s html=xdg-open

# Global alias: pipe anything to the clipboard (swap for wl-copy on Wayland)
alias -g C='| xclip -selection clipboard'

# Copy the current command line to the clipboard (Ctrl+X Ctrl+C)
function copy-buffer-to-clipboard() {
    print -rn -- "$BUFFER" | xclip -selection clipboard
    zle -M "Copied to clipboard"
}
zle -N copy-buffer-to-clipboard
bindkey '^X^C' copy-buffer-to-clipboard
