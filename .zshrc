export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="spaceship"

zstyle ':omz:update' mode reminder
zstyle ':omz:update' frequency 1

ENABLE_CORRECTION="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git alias-tips zsh-completions zsh-autosuggestions zsh-syntax-highlighting)

fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

source $ZSH/oh-my-zsh.sh

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
alias ohmyzsh="code-insiders $HOME/.zshrc"

# Python 3
alias pip=/usr/bin/pip3
alias python=/usr/bin/python3

alias c="code-insiders ."
alias sl="eza --icons"
alias l="eza --icons"
alias ll="eza --icons -la -snew"
alias lt="eza --icons --tree"
alias lz="eza --icons -la -s=size"
alias k="clear"
alias wip="git add . && git commit -m 'wip' && git push"
alias up="rustup update && bun upgrade && brew update && brew upgrade --greedy && omz update"
alias rmnode="find . -name 'node_modules' -type d -prune -exec rm -rf '{}' +"
alias rmnext="find . -name '.next' -type d -prune -exec rm -rf '{}' +"
alias rmdist="find . -name 'dist' -type d -prune -exec rm -rf '{}' +"
alias rmstore="find . -name '.DS_Store' -type f -delete"
alias rmts="find . -name 'tsconfig.tsbuildinfo' -type f -delete"
alias rmall="rmnode && rmnext && rmdist && rmstore && rmts"
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
alias vlog="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all"

eval "$(fnm env --use-on-cd)"
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

source /Users/yovanoc/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# bun completions
[ -s "/Users/yovanoc/.bun/_bun" ] && source "/Users/yovanoc/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
