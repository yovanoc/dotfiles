# PATH assembly. Everything that tool installers like to append to .zshrc lives here.
#
# `path` is tied to PATH (and `fpath` to FPATH); -U makes them dedupe automatically, keeping
# the first occurrence. That means re-sourcing .zshrc can never grow PATH again, and any
# duplicate inherited from .zshenv gets collapsed here.
typeset -U path PATH fpath FPATH

# bun
export BUN_INSTALL="$HOME/.bun"
path=("$BUN_INSTALL/bin" $path)
[[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"

# pnpm — macOS installs under ~/Library, Linux under the XDG data dir
if [[ $OSTYPE == darwin* ]]; then
    export PNPM_HOME="$HOME/Library/pnpm"
else
    export PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
fi
path=("$PNPM_HOME" $path)

# deno
[[ -r "$HOME/.deno/env" ]] && source "$HOME/.deno/env"
[[ -d "$HOME/.zsh/completions" ]] && fpath=("$HOME/.zsh/completions" $fpath)

# windsurf
path=("$HOME/.codeium/windsurf/bin" $path)

# own binaries last, so they win
path=("$HOME/.local/bin" $path)
