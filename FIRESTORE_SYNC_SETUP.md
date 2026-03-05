# Firestore Sync Setup (Prototype)

This branch adds a first-pass Firestore sync engine for WispMark.

## 1) Install Firebase CLI

```bash
npm install -g firebase-tools
firebase --version
firebase login
```

## 2) Select your Firebase project

```bash
firebase use --add
```

## 3) Create/enable Firestore and deploy rules

```bash
firebase deploy --only firestore
```

This deploys:
- `firestore.rules`
- `firestore.indexes.json`

## 4) Configure WispMark sync locally

You can configure Firebase values without editing tracked files:

```bash
defaults write com.andybarenberg.WispMark WispMark.Sync.FirebaseAppID "1:1234567890:ios:abcdef123456"
defaults write com.andybarenberg.WispMark WispMark.Sync.FirebaseSenderID "1234567890"
defaults write com.andybarenberg.WispMark WispMark.Sync.FirebaseAPIKey "AIza..."
defaults write com.andybarenberg.WispMark WispMark.Sync.FirebaseProjectID "your-firebase-project-id"
defaults write com.andybarenberg.WispMark WispMark.Sync.FirebaseStorageBucket "your-firebase-project-id.appspot.com"

defaults write com.andybarenberg.WispMark WispMark.Sync.Enabled -bool true
defaults write com.andybarenberg.WispMark WispMark.Sync.SpaceID "YOUR_LONG_RANDOM_SYNC_SPACE_ID"
```

Use the same `WispMark.Sync.SpaceID` on every Mac you want to sync.

## 5) Build and run

```bash
xcodegen generate --spec project.yml
xcodebuild -project WispMark-macOS.xcodeproj -scheme WispMark -configuration Debug build
```

## 6) Security notes

Current rules use a shared secret-style `spaceId` gate for fast prototyping.

- This is acceptable for prototype testing with a long random space ID.
- It is **not** the final production model.
- Next step is Firebase Auth + user-owned rules (`request.auth.uid`).

## 7) Optional local emulator

```bash
firebase emulators:start --only firestore
```
