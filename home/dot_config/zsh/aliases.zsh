# Aliases, suffix aliases, global aliases and directory bookmarks.

# Type a filename to open it with the associated program. bat and jless are not always
# installed, so fall back — install them and these pick them up automatically.
if (( $+commands[bat] )); then
    alias -s {md,txt,log}=bat
else
    alias -s {md,txt,log}=less
fi
if (( $+commands[jless] )); then
    alias -s json=jless
else
    alias -s json='jq .'
fi
alias -s {go,rs,js,ts}='$EDITOR'

# Global aliases — usable anywhere in a command, not just the first word
alias -g NE='2>/dev/null'      # discard stderr
alias -g NO='>/dev/null'       # discard stdout
alias -g NUL='>/dev/null 2>&1' # discard both
alias -g J='| jq'
# (the clipboard alias C is OS-specific and lives in os/{macos,linux}.zsh)

# zmv — batch rename/move with patterns
#   zmv '(*).log' '$1.txt'   rename .log to .txt
#   zmv -w '*.log' '*.txt'   same thing, simpler syntax
#   zmv -n ...               dry run
#   zmv -i ...               confirm each
autoload -Uz zmv
alias zcp='zmv -C' # copy with patterns
alias zln='zmv -L' # link with patterns

# Directory bookmarks — use as ~pj, ~dot, ~dl
hash -d pj=~/Projects
hash -d dot=~/dotfiles
hash -d dl=~/Downloads

# Editor / listing
alias c="code-insiders ."
alias sl="eza --icons"
alias l="eza --icons"
alias ll="eza --icons -la -snew"
alias lt="eza --icons --tree"
alias lz="eza --icons -la -s=size"
alias k="clear"

# git
alias wip="git add . && git commit -m 'wip' && git push"
alias vlog="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all"

# node / toolchain
alias p="pnpm"
alias up="rustup update && bun upgrade && brew update --force && brew upgrade --greedy"
alias pclean="pnpm clean && rmall && rm pnpm-lock.yaml && pnpm i && pnpm build && pnpm format"

# exec, not source: re-sourcing cannot remove an alias or function deleted from the file
alias s="exec zsh"

# docker
alias dkps="docker ps"
alias dkst="docker stats"
alias dkpsa="docker ps -a"
alias dkimgs="docker images"
alias dkcpup="docker compose up -d"
alias dkcpdown="docker compose down"
alias dkcpstart="docker compose start"
alias dkcpstop="docker compose stop"
alias dk-clean-unused='docker system prune --all --force --volumes'
alias dk-clean-all='docker stop $(docker container ls -a -q) && docker system prune -a -f --volumes'
alias dk-clean-containers='docker container stop $(docker container ls -a -q) && docker container rm $(docker container ls -a -q)'
alias dk-clean='dk-clean-unused && docker builder prune -af && docker buildx prune -af'
alias lzd="lazydocker"

# kubernetes
alias kb="kubectl"
alias mk="minikube"
alias createkh='tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"'
