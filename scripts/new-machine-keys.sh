#!/usr/bin/env bash
# Generate the SSH and GPG keys a new machine needs, then upload them to GitHub.
# Idempotent: existing keys are reused, never overwritten.

set -euo pipefail

command -v chezmoi >/dev/null || { echo "run scripts/install.sh first" >&2; exit 1; }
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

# gh is in the Brewfile; when it is authenticated this replaces the old
# copy-to-clipboard-and-open-a-browser step.
if gh auth status >/dev/null 2>&1; then
  title=$(hostname -s)
  gh ssh-key add "$key.pub" --title "$title" || echo "ssh upload failed (already added, or run: gh auth refresh -s admin:public_key)"
  gpg --armor --export "$fpr" | gh gpg-key add - || echo "gpg upload failed (already added, or run: gh auth refresh -s admin:gpg_key)"
else
  echo "gh not authenticated; add these manually at https://github.com/settings/keys"
  cat "$key.pub"
  gpg --armor --export "$fpr"
fi

echo
echo "signing key: $fpr"
echo "record it so git signs commits:  chezmoi init --prompt"
