#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

if command -v brew >/dev/null 2>&1; then
  BREW=$(command -v brew)
elif [[ -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW=/usr/local/bin/brew
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW=/opt/homebrew/bin/brew
  else
    BREW=/usr/local/bin/brew
  fi
fi

eval "$("$BREW" shellenv)"
"$BREW" install chezmoi
# init generates ~/.config/chezmoi/chezmoi.toml (identity prompts + sourceDir),
# so later chezmoi runs need no --source flag.
exec chezmoi --source "$ROOT" init --apply --interactive "$@"
