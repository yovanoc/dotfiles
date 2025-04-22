if [[ "($uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Added by OrbStack: command-line tools and integration
source ~/.orbstack/shell/init.zsh 2>/dev/null || :

export GPG_TTY=$(tty)
gpgconf --launch gpg-agent

ssh-add --apple-use-keychain ~/.ssh/github
