#!/bin/sh
set -e

# Navigate to project root
cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter via git, pinned to a known-working version.
# Flutter 3.44+ moves many plugins (Firebase, image_picker, etc.) to Swift
# Package Manager by default. The Runner Xcode project is still wired up for
# CocoaPods integration of those plugins, so a 3.44+ build fails with
# "Module 'cloud_firestore' not found" at GeneratedPluginRegistrant.m.
# Bump this pin only after migrating the iOS project to SPM.
FLUTTER_VERSION="3.41.1"
git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Precache iOS artifacts and get dependencies
flutter precache --ios
flutter pub get

# Regenerate Pods with correct paths for this environment.
# --no-repo-update skips refreshing the local spec repo; resolution comes from
# the checked-in Podfile.lock. Note ios/Pods itself is gitignored and untracked,
# despite what an earlier version of this comment claimed.
cd ios && pod install --no-repo-update

exit 0
