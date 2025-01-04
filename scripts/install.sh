#!/bin/sh

mkdir ~/Pictures/Screenshots
defaults write com.apple.screencapture location ~/Pictures/Screenshots
defaults write com.apple.finder AppleShowAllFiles YES
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true


# Install Homebrew
echo "Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Tapping repos
brew tap teamookla/speedtest

# Tools
tools=(
  gh
  watch
  pinentry-mac
  cmake
  gnupg
  tokei
  neovim
  speedtest
  protobuf
  hyperfine
  helmfile
  kustomize
  argocd
  ripgrep
  fd
  btop
  wget
  eza
  fzf
  oha
  fnm
  zoxide
  tmux
  lazygit
  stow
  delta
  pass
  ghostty
  jandedobbeleer/oh-my-posh/oh-my-posh
  lazydocker
)

# Install Tools
echo "installing tools..."
brew install ${tools[@]}

# Apps
apps=(
  alacritty
  discord
  visual-studio-code@insiders
  postico
  orbstack
  medis
  ledger-live
  raycast
  arc
)

# Install apps to /Applications
# Default is: /Users/$user/Applications
echo "Installing Apps..."
brew install --appdir="/Applications" --cask ${apps[@]}

# Fonts
fonts=(
  font-fira-code
  font-fira-code-nerd-font
  font-jetbrains-mono
  font-jetbrains-mono-nerd-font
  font-monaspace
  font-geist
  font-geist-mono
  font-geist-mono-nerd-font
)

# Install Fonts
echo "Installing Fonts..."
brew install ${fonts[@]}

# Some plugins
echo "Installing plugins..."

cd

fnm completions --shell zsh

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "All done! Happy hacking!"
