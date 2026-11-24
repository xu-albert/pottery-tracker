#!/bin/sh
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  echo "Skipping Crashlytics dSYM upload (CI_XCODEBUILD_ACTION=${CI_XCODEBUILD_ACTION:-unset})."
  exit 0
fi

UPLOAD_SYMBOLS="${CI_PRIMARY_REPOSITORY_PATH:-}/ios/Pods/FirebaseCrashlytics/upload-symbols"
GOOGLE_SERVICE_PLIST="${CI_PRIMARY_REPOSITORY_PATH:-}/ios/Runner/GoogleService-Info.plist"
DSYMS_DIR="${CI_ARCHIVE_PATH:-}/dSYMs"

if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ] || [ ! -x "$UPLOAD_SYMBOLS" ]; then
  echo "Crashlytics upload-symbols binary not found at '$UPLOAD_SYMBOLS'; cannot upload dSYMs." >&2
  exit 1
fi

if [ ! -f "$GOOGLE_SERVICE_PLIST" ]; then
  echo "GoogleService-Info.plist not found at '$GOOGLE_SERVICE_PLIST'; cannot upload dSYMs." >&2
  exit 1
fi

if [ -z "${CI_ARCHIVE_PATH:-}" ] || [ ! -d "$DSYMS_DIR" ]; then
  echo "Archive dSYMs directory not found at '$DSYMS_DIR'; cannot upload dSYMs." >&2
  exit 1
fi

echo "Uploading iOS dSYMs to Firebase Crashlytics from $DSYMS_DIR..."
"$UPLOAD_SYMBOLS" -gsp "$GOOGLE_SERVICE_PLIST" -p ios "$DSYMS_DIR"
