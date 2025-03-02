# Source/Load zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found

# Load completions
autoload -Uz compinit && compinit

zinit cdreplay -q

if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
    eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/themes/catppuccin_mocha.omp.json)"
    # eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/themes/zen.toml)"
fi

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

if [[ -n $SSH_CONNECTION ]]; then
    export EDITOR='vim'
else
    export EDITOR='nvim'
fi

# TurboRepo
export FORCE_COLOR=1

export MY_NAME="Christopher Yovanovitch"
export MY_EMAIL="yovano_c@outlook.com"

# GIT
GIT_AUTHOR_NAME=$MY_NAME
GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
git config --global user.name "$GIT_AUTHOR_NAME"
GIT_AUTHOR_EMAIL=$MY_EMAIL
GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git config --global user.email "$GIT_AUTHOR_EMAIL"
git config --global core.editor "code-insiders --wait"
git config --global commit.gpgSign true
git config --global tag.gpgSign true

# Create a new directory and enter it
function mkd() {
    mkdir -p "$@" && cd "$_"
}

function gcur() {
    git stash && git co dev && git pull && git checkout - && git rebase dev && git stash pop
}

function gnew() {
    git stash && git co dev && git pull && git checkout -b $1 && git stash pop && git add . && git commit
}

function gpr() {
    git push && git pull-request
}

function ka() {
    cnt=$(p $1 | wc -l) # total count of processes found
    klevel=${2:-15}     # kill level, defaults to 15 if argument 2 is empty

    echo -e "\nSearching for '$1' -- Found" $cnt "Running Processes .. "
    p $1

    echo -e '\nTerminating' $cnt 'processes .. '

    ps aux | grep -i $1 | grep -v grep | awk '{print $2}' | xargs sudo kill -klevel
    echo -e "Done!\n"

    echo "Running search again:"
    p "$1"
    echo -e "\n"
}

function dks() {
    watch -n 1 'STATS=$(docker stats --no-stream --format "table {{.Name}}\t{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"); echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k3hr) | head; echo; echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k4hr) | head; echo; echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k7hr) | head; echo; echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k10hr) | head;';
}

function port() {
    ps aux | grep -i $1 | grep -v grep
}

# Basics
alias zshconfig="code-insiders $HOME/.zshrc"

# Python 3
# alias pip=/usr/bin/pip3
# alias python=/usr/bin/python3

# Aliases
alias c="code-insiders ."
alias sl="eza --icons"
alias l="eza --icons"
alias ll="eza --icons -la -snew"
alias lt="eza --icons --tree"
alias lz="eza --icons -la -s=size"
alias k="clear"
alias wip="git add . && git commit -m 'wip' && git push"
alias up="rustup update && bun upgrade && brew update && brew upgrade --greedy"
alias rmnode="find . -name 'node_modules' -type d -prune -exec rm -rf '{}' +"
alias rmnext="find . -name '.next' -type d -prune -exec rm -rf '{}' +"
alias rmdist="find . -name 'dist' -type d -prune -exec rm -rf '{}' +"
alias rmturbo="find . -name '.turbo' -type d -prune -exec rm -rf '{}' +"
alias rmstore="find . -name '.DS_Store' -type f -delete"
alias rmtarget="find . -name 'target' -type d -prune -exec rm -rf '{}' +"
alias rmts="find . -name 'tsconfig.tsbuildinfo' -type f -delete"
alias rmall="rmnode && rmnext && rmdist && rmstore && rmts && rmturbo"
alias pclean="pnpm clean && rmall && rm pnpm-lock.yaml && pnpm i && pnpm build && pnpm format"
alias p="pnpm"
alias s="source $HOME/.zshrc"
alias dkps="docker ps"
alias dkst="docker stats"
alias dkpsa="docker ps -a"
alias dkimgs="docker images"
alias dkcpup="docker-compose up -d"
alias dkcpdown="docker-compose down"
alias dkcpstart="docker-compose start"
alias dkcpstop="docker-compose stop"
alias dk-clean-unused='docker system prune --all --force --volumes'
alias dk-clean-all='docker stop $(docker container ls -a -q) && docker system prune -a -f --volumes'
alias dk-clean-containers='docker container stop $(docker container ls -a -q) && docker container rm $(docker container ls -a -q)'
alias kb="kubectl"
alias mk="minikube"
alias lzd="lazydocker"
alias vlog="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all"
alias createkh='tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"'

# Shell integrations
eval "$(fnm env --use-on-cd)"
eval "$(zoxide init zsh)"
eval "$(fzf --zsh)"

# bun completions
[ -s "/Users/yovanoc/.bun/_bun" ] && source "/Users/yovanoc/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/yovanoc/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export PATH="$HOME/.local/bin:$PATH"

# Add deno completions to search path
if [[ ":$FPATH:" != *":/Users/yovanoc/.zsh/completions:"* ]]; then export FPATH="/Users/yovanoc/.zsh/completions:$FPATH"; fi

. "/Users/yovanoc/.deno/env"
