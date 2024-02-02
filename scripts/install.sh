#!/bin/sh

# Install ZSH
echo "Installing ZSH ..."
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
  cloc
  neovim
  cloc
  speedtest
  protobuf
  ripgrep
  btop
  eza
  oha
  fnm
  zoxide
  starship
  tmux
  lazygit
  stow
)

# Install Tools
echo "installing tools..."
brew install ${tools[@]}

# Apps
apps=(
  discord
  visual-studio-code-insiders
  postico
  orbstack
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

git clone https://github.com/spaceship-prompt/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"

git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
echo "source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ${ZDOTDIR:-$HOME}/.zshrc

git clone https://github.com/djui/alias-tips.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/alias-tips

cd

fnm completions --shell zsh

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "Install Vercel Geist Fonts, Raycast & Arc Browser and happy hacking!"
