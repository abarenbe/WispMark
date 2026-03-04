# WispMark Mac App Store + Direct Distribution Plan

## Overview
Dual-distribution strategy for WispMark macOS app:
- **App Store version (free)**: Sandboxed, no text injection, for visibility/discoverability
- **Direct version (paid)**: Notarized, full features including text injection, sold via website

## Prerequisites

### 1. Apple Developer Program
- [ ] Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) ($99/year)
- [ ] Complete enrollment verification (24-48 hours)

### 2. Create Website & Privacy Policy
- [ ] Set up floatmd.com (or similar)
- [ ] Write and host privacy policy (required for App Store)
- [ ] Set up payment processing for direct sales (Gumroad, Paddle, or Stripe)

---

## Phase 1: Xcode Project Setup

The current app is a single `main.swift` file. Need to create proper Xcode project structure.

### 1.1 Create Xcode Project
- [ ] Create new macOS App project in Xcode
- [ ] Bundle ID: `com.andybarenberg.floatmd` (App Store) / `com.andybarenberg.floatmd-pro` (Direct)
- [ ] Add `main.swift` code to project
- [ ] Configure build settings for macOS 12.0+ deployment target
- [ ] Add app icon to Assets.xcassets

### 1.2 Build Configuration for Two Versions
- [ ] Create two targets or use build configurations:
  - `WispMark` (App Store) - sandboxed, injection disabled
  - `WispMark Pro` (Direct) - not sandboxed, full features
- [ ] Use compiler flags (e.g., `#if APPSTORE`) to conditionally compile injection code

---

## Phase 2: App Store Version

### 2.1 Code Changes for Sandbox
- [ ] Remove or gate `CGEvent` text injection code behind `#if !APPSTORE`
- [ ] Remove `AXIsProcessTrustedWithOptions` check (not needed without injection)
- [ ] Remove "Injection Settings" UI section
- [ ] Remove injection hotkey functionality
- [ ] Keep: floating panel, notes, markdown, themes, toggle hotkey

### 2.2 Entitlements (App Store)
Create `WispMark.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

### 2.3 Code Signing
- [ ] Set Development Team in Xcode
- [ ] Signing: "Automatically manage signing"
- [ ] Distribution: "App Store Connect"

### 2.4 App Store Connect Setup
- [ ] Create app record in App Store Connect
- [ ] App name: "WispMark" (or "WispMark - Floating Notes")
- [ ] Category: Productivity
- [ ] Price: Free
- [ ] Prepare screenshots (1280x800, 1440x900, 2560x1600, 2880x1800)
- [ ] Write description mentioning "Pro version at floatmd.com" subtly
- [ ] Add privacy policy URL

### 2.5 Submit for Review
- [ ] Archive in Xcode (Product → Archive)
- [ ] Upload to App Store Connect
- [ ] Submit for review with notes: "Menu bar app for quick markdown notes"

---

## Phase 3: Direct Distribution Version (Pro)

### 3.1 Entitlements (Direct)
Create `WispMark-Pro.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```
Note: No sandbox required for direct distribution.

### 3.2 Code Signing & Notarization
- [ ] Enable "Hardened Runtime" in Xcode
- [ ] Sign with "Developer ID Application" certificate
- [ ] Notarize via:
  ```bash
  xcrun notarytool submit WispMark-Pro.zip --apple-id YOUR_ID --team-id TEAM_ID --password APP_SPECIFIC_PASSWORD --wait
  xcrun stapler staple WispMark-Pro.app
  ```

### 3.3 Distribution
- [ ] Create DMG or ZIP for download
- [ ] Host on website
- [ ] Set up payment (one-time purchase recommended, ~$5-15)
- [ ] Provide download link after purchase

### 3.4 Updates (Optional)
- [ ] Integrate Sparkle framework for auto-updates
- [ ] Host appcast.xml on your server

---

## Phase 4: Future - Cloud Sync (Optional)

For cross-platform sync (Mac + Windows web app):

### 4.1 Backend Setup
- [ ] Create Supabase project (free tier: 500MB, 50k requests/mo)
- [ ] Set up notes table with user authentication
- [ ] Implement REST API calls in app

### 4.2 Pricing Model
- Free (local only) → Paid sync subscription
- Keeps backend costs covered by paying users

### 4.3 Web App for Windows Access
- [ ] Build simple web interface to view/edit notes
- [ ] Accessible from classroom computer browser

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `main.swift` | Add `#if APPSTORE` conditionals around injection code |
| `WispMark.xcodeproj` | New - Xcode project with two targets/configs |
| `WispMark.entitlements` | New - App sandbox for App Store |
| `WispMark-Pro.entitlements` | New - Hardened runtime for direct |
| `Assets.xcassets` | Add app icons |
| `Info.plist` | Configure for each version |

---

## Cost Summary

| Item | Cost |
|------|------|
| Apple Developer Program | $99/year |
| Free app downloads | $0 |
| Direct sales | You keep 100% |
| Supabase (future sync) | Free tier, then $25/mo if needed |

---

## Launch Checklist

- [ ] Developer account active
- [ ] Privacy policy hosted
- [ ] App Store version submitted
- [ ] Direct version notarized and hosted
- [ ] Payment processing set up
- [ ] Website live with both versions mentioned
