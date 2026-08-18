#!/bin/sh
set -eu

if [ "$(uname -s)" = Darwin ]; then
  mkdir -p "$HOME/Pictures/Screenshots"
  defaults write com.apple.screencapture location "$HOME/Pictures/Screenshots"
  defaults write com.apple.finder AppleShowAllFiles YES
  defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
fi

if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

if [ ! -d "$HOME/.tmux/plugins/tpm/.git" ]; then
  mkdir -p "$HOME/.tmux/plugins"
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi
