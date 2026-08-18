# Keybindings and ZLE widgets. Sourced before the fzf integration, so fzf's own bindings
# (Ctrl+R, Ctrl+T) still win where they overlap.

bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# Ctrl+X Ctrl+E — open the current command line in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Undo is Ctrl+_ and is built in; redo has a widget but no default binding.
bindkey '^Y' redo

# Expand history expressions like !! or !$ on space
bindkey ' ' magic-space

# Ctrl+X Ctrl+L — clear screen and scrollback, keeping the current command buffer
function clear-screen-and-scrollback() {
    echoti civis >"$TTY"
    printf '%b' '\e[H\e[2J\e[3J' >"$TTY"
    echoti cnorm >"$TTY"
    zle redisplay
}
zle -N clear-screen-and-scrollback
bindkey '^X^L' clear-screen-and-scrollback

# Text snippets. \C-b moves the cursor back one position, so the quotes land around it.
bindkey -s '^Xgc' 'git commit -m ""\C-b'
bindkey -s '^Xgp' 'git push origin '
bindkey -s '^Xgs' 'git status\n'
bindkey -s '^Xgl' 'git log --oneline -n 10\n'
