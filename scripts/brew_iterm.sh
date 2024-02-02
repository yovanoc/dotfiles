#!/bin/sh

# Install Homebrew
echo "Installing Homebrew..."
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Apps
apps=(
  iterm2
)

# Install apps to /Applications
# Default is: /Users/$user/Applications
echo "Installing Apps..."
brew cask install --appdir="/Applications" ${apps[@]}
