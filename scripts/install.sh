#!/bin/sh

echo "Installing ohmyzsh ..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

mkdir ~/Pictures/Screenshots
defaults write com.apple.screencapture location ~/Pictures/Screenshots
defaults write com.apple.finder AppleShowAllFiles YES
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

# Tapping cask versions and fonts
brew tap homebrew/cask-versions
brew tap homebrew/cask-fonts
brew tap teamookla/speedtest

# Tools
tools=(
  github/gh/gh
  watch
  pinentry-mac
  gnupg
  gnupg2
  tokei
  neovim
  speedtest
  protobuf
  hyperfine
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
  jandedobbeleer/oh-my-posh/oh-my-posh
)

# Install Tools
echo "installing tools..."
brew install ${tools[@]}

# Apps
apps=(
  discord
  visual-studio-code@insiders
  postico
  orbstack
  medis
  ledger-live
)

# Install apps to /Applications
# Default is: /Users/$user/Applications
echo "Installing Apps..."
brew install --appdir="/Applications" ${apps[@]}

# Fonts
fonts=(
  font-fira-code
  font-fira-code-nerd-font
  font-jetbrains-mono
  font-jetbrains-mono-nerd-font
  font-monaspace
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

echo "Install Vercel Geist Fonts, Raycast & Arc Browser and happy hacking!"
