# WispMark Mac App Store Release

This project is now set up for Xcode archive/upload flow with App Sandbox enabled.

## 1) One-time Apple setup

1. Enroll in Apple Developer Program (already done).
2. In App Store Connect, create app record:
   - Platform: macOS
   - Bundle ID: `com.andybarenberg.WispMark` (or your final unique ID)
   - SKU: any unique internal value
3. Accept current agreements in App Store Connect.

## 2) Xcode project setup

1. Open `WispMark-macOS.xcodeproj` in Xcode.
2. Select target `WispMark` -> **Signing & Capabilities**:
   - Team: your Apple Developer team
   - Signing Certificate: Apple Distribution (automatic is fine)
   - Enable `Automatically manage signing`
3. Confirm bundle identifier matches App Store Connect record.
4. Set release versions in target **General**:
   - Version (`MARKETING_VERSION`), e.g. `1.0.0`
   - Build (`CURRENT_PROJECT_VERSION`), e.g. `1`

## 3) Sandbox behavior

App Sandbox is enabled via `WispMark.entitlements`.

- Local notes remain local-only.
- In sandboxed builds, app data lives in the app container.
- To import pre-sandbox notes, use menu item: **Import Notes Folder...** and select your old notes folder.

## 4) Archive + upload

### Option A (recommended): Xcode Organizer
1. Product -> Archive
2. Organizer -> select archive -> **Distribute App**
3. Choose **App Store Connect** -> **Upload**

### Option B (CLI archive)

```bash
xcodebuild \
  -project WispMark-macOS.xcodeproj \
  -scheme WispMark \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath build/WispMark.xcarchive \
  MARKETING_VERSION=1.0.0 \
  CURRENT_PROJECT_VERSION=1 \
  archive
```

## 5) App Store Connect submission checklist

1. Fill app metadata, privacy details, support URL, marketing URL (optional), screenshots.
2. Select uploaded build.
3. Complete export compliance and content rights prompts.
4. Submit for review.

## 6) Pre-submit checks

1. Launch archived build locally and verify:
   - Creating/saving notes
   - Restoring deleted notes
   - Global hotkeys
   - Import Notes Folder flow
2. Confirm App Sandbox entitlement is present:

```bash
codesign -d --entitlements :- "/path/to/WispMark.app"
```
