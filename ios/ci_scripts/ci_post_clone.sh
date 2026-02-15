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

# Regenerate Pods with correct paths for this environment.
# --no-repo-update skips CDN access (Xcode Cloud can't reach cdn.jsdelivr.net).
# Pods source code is checked into the repo so no downloads are needed.
cd ios && pod install --no-repo-update

exit 0
