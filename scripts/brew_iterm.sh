#!/bin/sh

# Install Homebrew
echo "Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apps
apps=(
  iterm2
)

# Install apps to /Applications
# Default is: /Users/$user/Applications
echo "Installing Apps..."
brew cask install --appdir="/Applications" ${apps[@]}
