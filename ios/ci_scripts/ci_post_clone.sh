#!/bin/sh
set -e

# Navigate to project root
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install Flutter via git
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

# Precache iOS artifacts and get dependencies
flutter precache --ios
flutter pub get

# Install CocoaPods dependencies
cd ios
pod install
