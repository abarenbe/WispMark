# Code Signing WispMark

WispMark no longer uses system text injection, so it does not require Accessibility/Input Monitoring permissions.
Code signing is still recommended for smoother launch behavior and trusted distribution.

## Recommended (Apple Developer Account)

Use your `Developer ID Application` certificate.

1. Confirm the identity exists:
```bash
security find-identity -v -p codesigning
```

2. Build and install:
```bash
./build_app.sh
```

`build_app.sh` now auto-detects the first `Developer ID Application` identity and signs `/Applications/WispMark.app` with it.

If you want to force a specific cert:
```bash
WISPMARK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build_app.sh
```

## Verify Signature

```bash
codesign -dv --verbose=4 /Applications/WispMark.app
```

You should see `Authority=Developer ID Application: ...`.

## Fallback (No Developer ID Available)

`build_app.sh` falls back to ad-hoc signing (`-`) if no identity is found. This works for local testing.

## Mac App Store Distribution

Mac App Store builds should be produced from `WispMark-macOS.xcodeproj` using Xcode Archive/Organizer, not `build_app.sh`.

See [`APP_STORE.md`](APP_STORE.md) for the full archive/upload checklist.
