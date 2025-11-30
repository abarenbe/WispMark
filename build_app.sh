#!/bin/bash
set -e

APP_NAME="FloatMD"
APP_DIR="$APP_NAME.app"
BINARY_NAME="FloatMD"
ICON_SOURCE="logo_float.png"

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
    <string>com.andybarenberg.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
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
    ICONSET_DIR="FloatMD.iconset"
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

echo "Creating entitlements..."
cat > "FloatMD.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

echo "Code signing app (ad-hoc)..."
codesign --force --deep --sign - --entitlements FloatMD.entitlements "$APP_DIR"

echo "Build complete: $APP_DIR"

echo "Installing to /Applications..."
# Check if we should use a developer certificate
SIGN_IDENTITY="${FLOATMD_SIGN_IDENTITY:--}"

if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "Using signing identity: $SIGN_IDENTITY"
fi

# Remove existing app if present
if [ -d "/Applications/$APP_NAME.app" ]; then
    rm -rf "/Applications/$APP_NAME.app"
fi
cp -R "$APP_DIR" "/Applications/"

# Re-sign after copy
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements FloatMD.entitlements "/Applications/$APP_NAME.app" 2>/dev/null || \
codesign --force --deep --sign "$SIGN_IDENTITY" "/Applications/$APP_NAME.app"

rm -f FloatMD.entitlements

echo "Done! FloatMD has been installed to /Applications."
