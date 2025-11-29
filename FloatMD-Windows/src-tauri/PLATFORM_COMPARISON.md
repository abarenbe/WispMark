# Platform Comparison: macOS Swift vs Windows Rust

This document maps FloatMD features between the macOS (Swift) and Windows (Rust/Tauri) implementations.

## Data Model

### Note Structure

| Feature | macOS (Swift) | Windows (Rust) |
|---------|---------------|----------------|
| ID | `UUID` | `Uuid` (from uuid crate) |
| Content | `String` | `String` |
| Created Date | `Date` | `DateTime<Utc>` (chrono) |
| Modified Date | `Date` | `DateTime<Utc>` (chrono) |
| Pinned Status | `Bool` | `bool` |
| JSON Keys | `createdAt`, `modifiedAt` | `createdAt`, `modifiedAt` (via serde rename) |

Both implementations use the **same JSON format**, allowing notes to be copied between platforms.

---

## Storage

### macOS (Swift)
```swift
// AppDelegate or NotesManager
func applicationSupportDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FloatMD")
}

let notesURL = applicationSupportDirectory().appendingPathComponent("notes.json")
```

### Windows (Rust)
```rust
// storage.rs
pub fn get_storage_path() -> Result<PathBuf> {
    // Check for portable mode (.portable file or data/ folder)
    if portable_marker.exists() || data_dir.exists() {
        return exe_dir.join("data/notes.json");
    }

    // Standard mode - AppData
    dirs::data_dir()
        .join("FloatMD")
        .join("notes.json")
}
```

**Key Difference:** Windows implementation adds portable mode support for USB drives.

---

## Window Management

### macOS (Swift)
```swift
// AppDelegate
func applicationDidFinishLaunching(_ notification: Notification) {
    setupWindow()
    setupStatusBar()
}

func setupWindow() {
    window.level = .floating  // Always on top
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
}
```

### Windows (Tauri)
```json
// tauri.conf.json
{
  "app": {
    "windows": [{
      "alwaysOnTop": false,  // User can toggle
      "skipTaskbar": false
    }]
  }
}
```

```rust
// main.rs - Hide on close instead of quit
.on_window_event(|window, event| {
    if let WindowEvent::CloseRequested { api, .. } = event {
        window.hide().unwrap();
        api.prevent_close();
    }
})
```

---

## System Tray / Menu Bar

### macOS (Swift)
```swift
// Status bar item
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(named: "MenuBarIcon")

let menu = NSMenu()
menu.addItem(NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: ""))
menu.addItem(NSMenuItem(title: "Show/Hide", action: #selector(toggle), keyEquivalent: ""))
```

### Windows (Rust/Tauri)
```rust
// main.rs
fn create_tray_menu(app: &AppHandle) {
    let menu = Menu::with_items(app, &[
        MenuItem::with_id(app, "new_note", "New Note", true, None)?,
        MenuItem::with_id(app, "toggle", "Show/Hide", true, None)?,
    ])?;

    TrayIconBuilder::new()
        .menu(&menu)
        .on_menu_event(|app, event| { /* handle */ })
        .build(app)?;
}
```

**Similar functionality, different APIs.**

---

## Global Hotkeys

### macOS (Swift)
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleWindow = Self("toggleWindow")
    static let injectText = Self("injectText")
}

KeyboardShortcuts.onKeyUp(for: .toggleWindow) {
    toggleWindow()
}

KeyboardShortcuts.onKeyUp(for: .injectText) {
    injectSelectedNote()
}
```

### Windows (Rust/Tauri)
```rust
// hotkeys.rs
use tauri_plugin_global_shortcut::{Shortcut, Code, Modifiers};

let toggle = Shortcut::new(
    Some(Modifiers::CONTROL | Modifiers::SHIFT),
    Code::KeyM
);

app.global_shortcut().on_shortcut(toggle, |app, _, _| {
    // Toggle window
})?;
```

**Default Hotkeys:**
- **macOS:** Cmd+Shift+M (toggle), Cmd+Alt+I (inject)
- **Windows:** Ctrl+Shift+M (toggle), Ctrl+Alt+I (inject)

---

## Text Injection

### macOS (Swift)
```swift
func injectText(_ text: String) {
    // Copy to clipboard
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    // Simulate Cmd+V
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)

    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.post(tap: .cghidEventTap)
}
```

### Windows (Rust)
```rust
// injection.rs
pub fn inject_text(text: &str) -> Result<()> {
    // Copy to clipboard (Win32 API)
    set_clipboard_text(text)?;

    // Simulate Ctrl+V using SendInput
    let mut inputs = [/* INPUT structs */];
    SendInput(&inputs, size_of::<INPUT>())?;
}
```

**Both use the same approach:** Clipboard + Keyboard simulation

---

## Markdown Features

The following are **frontend features** (not backend) and will be identical on both platforms:

- Wiki links `[[Note Name]]`
- Tags `#tag`
- Tag autocomplete
- Markdown rendering
- Search and filtering

---

## Architecture Comparison

### macOS
```
FloatMD.app
├── Swift App (AppDelegate)
├── SwiftUI Views
│   ├── NoteEditorView
│   ├── NotesListView
│   └── MarkdownRenderer
└── Models
    ├── Note
    └── NotesManager
```

**All-in-one:** Swift handles everything (UI, storage, hotkeys, injection)

### Windows
```
FloatMD
├── Rust Backend (Tauri)
│   ├── main.rs (tray, window)
│   ├── storage.rs (notes)
│   ├── hotkeys.rs (shortcuts)
│   └── injection.rs (text injection)
└── Frontend (React/Vue/Svelte)
    ├── UI Components
    ├── Markdown Rendering
    └── Tauri API Calls
```

**Separation:** Rust backend + JavaScript frontend communicate via Tauri commands

---

## Feature Parity Checklist

| Feature | macOS | Windows |
|---------|-------|---------|
| Create/Edit/Delete Notes | ✅ | ✅ |
| Persistent Storage | ✅ | ✅ |
| Pinned Notes | ✅ | ✅ |
| Global Hotkeys | ✅ | ✅ |
| Text Injection | ✅ | ✅ |
| System Tray/Menu Bar | ✅ | ✅ |
| Hide on Close | ✅ | ✅ |
| Markdown Rendering | ✅ | ✅ (Frontend) |
| Wiki Links | ✅ | ✅ (Frontend) |
| Tags | ✅ | ✅ (Frontend) |
| Search | ✅ | ✅ (Frontend) |
| **Portable Mode** | ❌ | ✅ |
| iCloud Sync | ✅ (macOS/iOS) | ❌ |

---

## Migration Path

To migrate notes from macOS to Windows:

1. **Locate macOS notes:**
   ```
   ~/Library/Application Support/FloatMD/notes.json
   ```

2. **Copy to Windows AppData:**
   ```
   %APPDATA%\FloatMD\notes.json
   ```

3. **Or use portable mode:**
   - Create `.portable` file next to FloatMD.exe
   - Place `notes.json` in `data/notes.json`

The JSON format is identical, so notes work immediately.

---

## Development Workflow

### macOS
```bash
# Edit Swift code
open FloatMD.xcodeproj

# Build and run
Cmd+R in Xcode
```

### Windows
```bash
# Edit Rust backend
code src-tauri/src/

# Edit frontend
code src/

# Run dev mode
npm run tauri dev

# Build
npm run tauri build
```

---

## Summary

Both implementations provide the **same user experience** with platform-appropriate technologies:

- **macOS:** Native Swift/SwiftUI, tightly integrated with system
- **Windows:** Tauri (Rust + Web), cross-platform foundation

The Windows version adds **portable mode** support, making it ideal for USB drives and corporate environments where AppData may be restricted.
