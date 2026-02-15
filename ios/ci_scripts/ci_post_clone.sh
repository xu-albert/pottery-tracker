#!/bin/sh
set -e

# Navigate to project root
cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter via git
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Precache iOS artifacts and get dependencies
flutter precache --ios
flutter pub get

# Install CocoaPods using Homebrew
HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods

# Install CocoaPods dependencies
cd ios && pod install

exit 0
