- [ ] Change name to FloatNote.
- [ ] use logo.png as icon for status bar item.
- [ ] make Command + N create a new note to be consistent with the status bar item.
- [ ] Cursor needs to contrast color with background to be visible.

---

# Windows Portable Version Plan

## Overview
Create a portable Windows version of FloatMD that runs without installation. The app should be a single executable or self-contained folder that users can run from anywhere (USB drive, Downloads folder, etc.).

## Recommended Technology Stack

### Option A: Electron + TypeScript (Recommended)
**Pros:** Cross-platform, rich ecosystem, familiar web tech, easy packaging
**Cons:** Larger bundle size (~100MB+)

### Option B: Tauri + Rust
**Pros:** Small bundle size (~10MB), native performance, security
**Cons:** Steeper learning curve, smaller ecosystem

### Option C: .NET MAUI / WPF
**Pros:** Native Windows, good performance, single executable possible
**Cons:** Windows-only (defeats future cross-platform), requires .NET runtime or self-contained publish

### Recommendation: **Tauri** for portable single-exe with small footprint

---

## Architecture Plan

### Phase 1: Core Infrastructure
- [ ] Set up Tauri project with TypeScript frontend
- [ ] Configure portable mode (store data in app directory, not AppData)
- [ ] Implement local JSON file storage for notes (same format as macOS)
- [ ] Create Note data model matching existing structure

### Phase 2: UI Components
- [ ] Main floating window (always-on-top capability)
- [ ] Note editor with textarea/contenteditable
- [ ] Notes list sidebar with search
- [ ] System tray icon with context menu
- [ ] Settings panel (themes, hotkeys, injection options)

### Phase 3: Markdown Features
- [ ] Real-time markdown syntax highlighting
- [ ] Wiki link support (`[[Title]]`) with navigation
- [ ] Tag extraction and display (`#tag`)
- [ ] Autocomplete popup for tags and wiki links
- [ ] Clickable checkboxes
- [ ] Theme system (port 5 existing themes)

### Phase 4: Windows-Specific Features
- [ ] Global hotkey registration (Windows API via Tauri)
- [ ] Text injection using Windows SendInput API
- [ ] System tray integration
- [ ] Window position persistence
- [ ] Portable mode detection (run from USB, etc.)

### Phase 5: Packaging & Distribution
- [ ] Configure single-exe build (Tauri supports this)
- [ ] Create portable ZIP distribution
- [ ] Optional: Create MSI installer for users who prefer it
- [ ] Auto-updater for portable version (optional)

---

## File Structure (Proposed)

```
FloatMD-Windows/
├── src-tauri/           # Rust backend
│   ├── src/
│   │   ├── main.rs      # App entry, window setup
│   │   ├── hotkeys.rs   # Global hotkey registration
│   │   ├── injection.rs # Text injection via SendInput
│   │   ├── storage.rs   # Portable file storage
│   │   └── tray.rs      # System tray management
│   ├── Cargo.toml
│   └── tauri.conf.json
├── src/                 # TypeScript/React frontend
│   ├── components/
│   │   ├── Editor.tsx
│   │   ├── NotesList.tsx
│   │   ├── Autocomplete.tsx
│   │   ├── TagPill.tsx
│   │   └── Settings.tsx
│   ├── models/
│   │   ├── Note.ts
│   │   └── NotesManager.ts
│   ├── themes/
│   │   └── index.ts     # 5 themes ported from macOS
│   ├── utils/
│   │   ├── markdown.ts  # Markdown parsing/highlighting
│   │   └── wikilinks.ts # Wiki link extraction
│   ├── App.tsx
│   └── main.tsx
├── package.json
└── README.md
```

---

## Key Implementation Details

### Portable Storage
```rust
// Detect if running portable (exe directory has a "data" folder or flag file)
fn get_storage_path() -> PathBuf {
    let exe_dir = std::env::current_exe().unwrap().parent().unwrap();
    let portable_marker = exe_dir.join(".portable");

    if portable_marker.exists() || exe_dir.join("data").exists() {
        exe_dir.join("data")
    } else {
        dirs::data_local_dir().unwrap().join("FloatMD")
    }
}
```

### Global Hotkeys (Windows)
```rust
use windows::Win32::UI::Input::KeyboardAndMouse::RegisterHotKey;
// Register Ctrl+Shift+M for toggle, Ctrl+Alt+I for inject, etc.
```

### Text Injection (Windows)
```rust
use windows::Win32::UI::Input::KeyboardAndMouse::SendInput;
// Copy to clipboard, then simulate Ctrl+V
```

---

## Platform Feature Mapping

| macOS Feature | Windows Equivalent |
|--------------|-------------------|
| NSPanel (floating) | WS_EX_TOPMOST window style |
| Carbon hotkeys | RegisterHotKey API |
| CGEvent (Cmd+V) | SendInput API (Ctrl+V) |
| NSStatusBar | System Tray (Shell_NotifyIcon) |
| NSPasteboard | Clipboard API |
| UserDefaults | JSON file in portable directory |

---

## Development Phases & Tasks

### Sprint 1: Foundation (Week 1)
1. Initialize Tauri + React project
2. Implement Note model and NotesManager
3. Create basic editor UI
4. Set up portable storage system
5. Test on Windows

### Sprint 2: Core Features (Week 2)
1. Markdown syntax highlighting
2. Wiki link parsing and navigation
3. Tag extraction and autocomplete
4. Notes list with search
5. Pin/unpin functionality

### Sprint 3: Windows Integration (Week 3)
1. Global hotkey registration
2. System tray with menu
3. Text injection feature
4. Floating window behavior
5. Settings UI

### Sprint 4: Polish & Package (Week 4)
1. Theme system implementation
2. Keyboard shortcuts
3. Edge cases and bug fixes
4. Single-exe packaging
5. Create portable ZIP release

---

## Build Commands

```bash
# Development
npm run tauri dev

# Production build (single exe)
npm run tauri build -- --bundles exe

# Create portable ZIP
# The .exe can be distributed standalone with a "data" folder
```

---

## Testing Checklist
- [ ] Runs from USB drive without installation
- [ ] Data persists in portable directory
- [ ] Global hotkeys work system-wide
- [ ] Text injection works in common apps (Notepad, Word, browser)
- [ ] System tray icon appears and responds
- [ ] Window stays on top when configured
- [ ] All 5 themes render correctly
- [ ] Wiki links navigate between notes
- [ ] Tags are extracted and searchable
- [ ] Search filters notes correctly 