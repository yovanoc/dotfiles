# Shell functions. Anything longer than a one-liner lives here rather than as an alias.

# Create a new directory and enter it
function mkd() {
    mkdir -p "$@" && cd "$_"
}

# `git co` was never defined as a git alias, so these silently failed at the step right after
# `git stash` — which quietly left your work sitting in the stash. Use real subcommands.
# Note: both assume `dev` is the base branch.
function gcur() {
    git stash && git checkout dev && git pull && git checkout - && git rebase dev && git stash pop
}

function gnew() {
    git stash && git checkout dev && git pull && git checkout -b $1 && git stash pop && git add . && git commit
}

# `git pull-request` is a hub(1) subcommand and is not installed here; gh is.
function gpr() {
    git push && gh pr create
}

# Process search by name
function psg() {
    ps aux | grep -i "$1" | grep -v grep
}

# What is listening on a port
function port() {
    lsof -nP -iTCP:"$1" -sTCP:LISTEN
}

# Kill every process matching a name. Second arg is the signal, default 15 (TERM).
function ka() {
    local cnt=$(psg "$1" | wc -l) # total count of processes found
    local klevel=${2:-15}         # kill level, defaults to 15 if argument 2 is empty

    echo -e "\nSearching for '$1' -- Found" $cnt "Running Processes .. "
    psg "$1"

    echo -e '\nTerminating' $cnt 'processes .. '
    psg "$1" | awk '{print $2}' | xargs sudo kill -"$klevel"
    echo -e "Done!\n"

    echo "Running search again:"
    psg "$1"
    echo -e "\n"
}

# Live docker stats, sorted by CPU / memory / net / block IO
function dks() {
    watch -n 1 'STATS=$(docker stats --no-stream --format "table {{.Name}}\t{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"); echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k3hr) | head; echo; echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k4hr) | head; echo; echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k7hr) | head; echo; echo "$STATS" | (read -r; printf "%s\n" "$REPLY"; sort -k10hr) | head;';
}

# Upload a file (or stdin) to paste.rs. Named pastebin, not paste, so it stops shadowing
# /usr/bin/paste (the POSIX column-merging tool).
function pastebin() {
    local file=${1:-/dev/stdin}
    curl --data-binary @${file} https://paste.rs
}

# Dotfiles drift. Both halves are silent when clean, and agents write to
# ~/.agents and ~/.pi constantly, so the divergence is otherwise invisible.
#   chezmoi status: first column = what changed in $HOME since chezmoi last
#   wrote it, so a chezmoi re-add candidate; second column = what chezmoi
#   apply will do. A added, D deleted, M modified, R script will run.
#   git status: the repo has changes no other machine can see yet.
function dots() {
    local drift repo
    drift=$(chezmoi status)
    repo=$(git -C ~/dotfiles status --short)
    [[ -n $drift ]] && print "unapplied/unadded:\n$drift"
    [[ -n $repo ]] && print "uncommitted:\n$repo"
    [[ -z $drift && -z $repo ]] && print "dotfiles clean"
}

# cd to the repository root
function cdgr() {
    cd "$(git rev-parse --show-toplevel)" || echo "Not a git repository"
}

# Purge build artefacts recursively from the current directory down.
# Skip unrelated hidden trees such as ~/.rustup when run from $HOME.
function rmall() {
    find . -mindepth 1 \( \
        -type d \( -name node_modules -o -name .next -o -name dist -o -name .turbo -o -name target \) -prune -exec rm -rf '{}' + \
        -o \
        -type d -name '.*' -prune \
        -o \
        -type f \( -name .DS_Store -o -name tsconfig.tsbuildinfo \) -exec rm -f '{}' + \
    \)
}
