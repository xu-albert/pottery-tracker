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

# Most pods arrive as HTTP tarballs, but several Firebase pods declare a git
# source and are fetched with `git clone`. Xcode Cloud has been observed routing
# git through a proxy on localhost:8088 that nothing is listening on, and
# rewriting https:// to http:// on the way — while plain HTTP downloads in the
# same run succeed. That combination fails the build at the first git-sourced
# pod (FirebaseABTesting), so neutralise it before installing.
#
# Every line tolerates being a no-op: on a machine without this config the
# unsets fail harmlessly, and `set -e` would otherwise abort the script.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
git config --global --unset-all http.proxy 2>/dev/null || true
git config --global --unset-all https.proxy 2>/dev/null || true
git config --global --remove-section 'url.http://' 2>/dev/null || true
# Counteract the observed scheme downgrade rather than relying on its absence.
git config --global url."https://github.com/".insteadOf "http://github.com/"

# Regenerate Pods with correct paths for this environment.
# --no-repo-update skips refreshing the local spec repo; resolution comes from
# the checked-in Podfile.lock. Note ios/Pods itself is gitignored and untracked,
# despite what an earlier version of this comment claimed.
cd ios && pod install --no-repo-update

exit 0
