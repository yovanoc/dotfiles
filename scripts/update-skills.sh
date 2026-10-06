#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

npx skills update --global
[[ -d $HOME/.agents/skills && -f $HOME/.agents/.skill-lock.json ]] || {
  echo 'Skills directory or lockfile missing; refusing to sync.' >&2
  exit 1
}
chezmoi --source "$PWD" forget --force "$HOME/.agents/skills"
chezmoi --source "$PWD" add --recursive --secrets error "$HOME/.agents/skills" "$HOME/.agents/.skill-lock.json"
