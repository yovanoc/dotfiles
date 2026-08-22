#!/usr/bin/env bash
# Generate the SSH and GPG keys a new machine needs, then upload them to GitHub.
# Idempotent: existing keys are reused, never overwritten.

set -euo pipefail

command -v chezmoi >/dev/null || {
  echo "run scripts/install.sh first" >&2
  exit 1
}
name=$(chezmoi data --format=json | jq -r '.name')
email=$(chezmoi data --format=json | jq -r '.email')
key=~/.ssh/github

echo "identity: $name <$email>"

if [[ -f $key ]]; then
  echo "ssh: $key already exists"
else
  echo "ssh: generating $key (enter a passphrase when prompted)"
  ssh-keygen -t ed25519 -C "$email" -f "$key"
  ssh-add --apple-use-keychain "$key"
fi

if gpg --list-secret-keys "$email" >/dev/null 2>&1; then
  echo "gpg: secret key for $email already exists"
else
  echo "gpg: generating a 2-year key"
  gpg --quick-generate-key "$name <$email>" default default 2y
fi
fpr=$(gpg --list-secret-keys --with-colons "$email" | awk -F: '/^fpr:/ {print $10; exit}')

# gh is in the Brewfile and a new machine needs it authenticated anyway, so
# log in here rather than falling back to copy-and-paste. Key upload needs
# scopes the default login does not request.
scopes="admin:public_key,admin:gpg_key"
if ! gh auth status >/dev/null 2>&1; then
  gh auth login --web --git-protocol ssh --scopes "$scopes"
fi
have=$(gh auth status 2>&1 | sed -n "s/.*Token scopes: //p")
if [[ $have != *admin:public_key* || $have != *admin:gpg_key* ]]; then
  echo "granting $scopes"
  gh auth refresh --scopes "$scopes"
fi

title=$(hostname -s)
gh ssh-key add "$key.pub" --title "$title" || echo "ssh key already on the account"
gpg --armor --export "$fpr" | gh gpg-key add - || echo "gpg key already on the account"

echo
echo "signing key: $fpr"
echo "record it so git signs commits:  chezmoi init --prompt"
