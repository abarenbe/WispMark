#!/bin/bash
set -euo pipefail

APP_NAME="WispMark"
STAGING_APP_PATH="build/Install/$APP_NAME.app"
PROJECT_PATH="WispMark-macOS.xcodeproj"
SCHEME_NAME="WispMark"
CONFIGURATION="${WISPMARK_CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="build/DerivedData"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_VERSION="${WISPMARK_VERSION:-1.0.0}"
BUILD_NUMBER="${WISPMARK_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
INSTALL_PATH="/Applications/$APP_NAME.app"

detect_sign_identity() {
    if [ -n "${WISPMARK_SIGN_IDENTITY:-}" ]; then
        echo "$WISPMARK_SIGN_IDENTITY"
        return
    fi

    local detected
    detected="$(security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/Developer ID Application/ {print $2; exit}')"
    if [ -n "$detected" ]; then
        echo "$detected"
    else
        echo "-"
    fi
}

set_plist_string() {
    local plist_path="$1"
    local key="$2"
    local value="$3"

    if /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist_path"
    else
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist_path"
    fi
}

SIGN_IDENTITY="$(detect_sign_identity)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Warning: No code-signing identity found. Falling back to ad-hoc signing."
else
    echo "Using signing identity: $SIGN_IDENTITY"
fi

echo "Building Xcode target..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [ ! -d "$BUILT_APP_PATH" ]; then
    echo "Build output not found: $BUILT_APP_PATH" >&2
    exit 1
fi

echo "Staging app bundle..."
rm -rf "$STAGING_APP_PATH"
mkdir -p "$(dirname "$STAGING_APP_PATH")"
ditto "$BUILT_APP_PATH" "$STAGING_APP_PATH"

INFO_PLIST="$STAGING_APP_PATH/Contents/Info.plist"
set_plist_string "$INFO_PLIST" "CFBundleShortVersionString" "$APP_VERSION"
set_plist_string "$INFO_PLIST" "CFBundleVersion" "$BUILD_NUMBER"
set_plist_string "$INFO_PLIST" "WispMarkGitCommit" "$GIT_COMMIT"

echo "Build metadata: version=$APP_VERSION build=$BUILD_NUMBER commit=$GIT_COMMIT"

echo "Code signing staged app..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGING_APP_PATH"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$STAGING_APP_PATH"
fi

echo "Installing to /Applications..."
rm -rf "$INSTALL_PATH"
ditto "$STAGING_APP_PATH" "$INSTALL_PATH"

echo "Code signing installed app..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$INSTALL_PATH"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$INSTALL_PATH"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"

echo "Done! WispMark has been installed to /Applications."
