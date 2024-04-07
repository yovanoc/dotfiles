
eval "$(/opt/homebrew/bin/brew shellenv)"

# Added by OrbStack: command-line tools and integration
source ~/.orbstack/shell/init.zsh 2>/dev/null || :

export GPG_TTY=$(tty)
gpgconf --launch gpg-agent

ssh-add --apple-use-keychain ~/.ssh/github
