#!/bin/bash
set -euo pipefail

APP_NAME="WispMark"
APP_DIR="$APP_NAME.app"
BINARY_NAME="WispMark"
ICON_SOURCE="logo_wispmark.png"
APP_BUNDLE_ID="com.andybarenberg.WispMark"
APP_VERSION="${WISPMARK_VERSION:-1.0.0}"
BUILD_NUMBER="${WISPMARK_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
INSTALL_PATH="/Applications/$APP_NAME.app"

detect_sign_identity() {
    if [ -n "${WISPMARK_SIGN_IDENTITY:-}" ]; then
        echo "$WISPMARK_SIGN_IDENTITY"
        return
    fi

    # Prefer a Developer ID Application identity if available.
    local detected
    detected="$(security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/Developer ID Application/ {print $2; exit}')"
    if [ -n "$detected" ]; then
        echo "$detected"
    else
        echo "-"
    fi
}

SIGN_IDENTITY="$(detect_sign_identity)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Warning: No code-signing identity found. Falling back to ad-hoc signing."
else
    echo "Using signing identity: $SIGN_IDENTITY"
fi

echo "Cleaning up..."
rm -rf "$APP_DIR"

echo "Creating App Bundle Structure..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "Compiling Swift Code..."
swiftc main.swift -o "$APP_DIR/Contents/MacOS/$BINARY_NAME" -framework Cocoa -framework Carbon -O

echo "Creating Info.plist..."
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>WispMarkGitCommit</key>
    <string>$GIT_COMMIT</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -f "$ICON_SOURCE" ]; then
    echo "Creating App Icon..."
    ICONSET_DIR="WispMark.iconset"
    mkdir -p "$ICONSET_DIR"

    # Resize images
    sips -s format png -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -s format png -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

    # Convert to icns
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    
    # Clean up
    rm -rf "$ICONSET_DIR"
else
    echo "Warning: $ICON_SOURCE not found. App will have generic icon."
fi

echo "Build metadata: version=$APP_VERSION build=$BUILD_NUMBER commit=$GIT_COMMIT"

echo "Code signing app..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP_DIR"
fi

echo "Build complete: $APP_DIR"

echo "Installing to /Applications..."

# Remove existing app if present
if [ -d "$INSTALL_PATH" ]; then
    rm -rf "$INSTALL_PATH"
fi
cp -R "$APP_DIR" "/Applications/"

# Re-sign after copy to ensure final installed app has the expected signature.
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$INSTALL_PATH"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$INSTALL_PATH"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"

echo "Done! WispMark has been installed to /Applications."
