# WispMark Windows - Tauri Rust Backend

This is the Rust backend for WispMark Windows application built with Tauri v2.

## Features

### Storage Module (`storage.rs`)
- **Portable Mode Detection**: Automatically detects if app should run in portable mode
  - Checks for `.portable` marker file next to executable
  - Checks for existing `data/` folder next to executable
  - Falls back to AppData if neither exists
- **Note Management**: Full CRUD operations for notes
- **Data Format**: JSON storage compatible with macOS/iOS versions
- **Note Structure**:
  - `id`: UUID v4
  - `content`: Markdown text
  - `created_at`: ISO 8601 timestamp
  - `modified_at`: ISO 8601 timestamp
  - `is_pinned`: Boolean

### Hotkeys Module (`hotkeys.rs`)
- **Ctrl+Shift+M**: Toggle window visibility
- **Ctrl+Alt+I**: Inject selected note text into active application
- Built on Tauri's global-shortcut plugin
- Extensible for custom hotkey registration

### Injection Module (`injection.rs`)
- **Platform-Specific**: Windows-only implementation using Win32 API
- **Two-Step Process**:
  1. Copy text to clipboard using Windows clipboard API
  2. Simulate Ctrl+V keypress using SendInput
- **Safe**: Includes proper delays and error handling

## Commands Available to Frontend

### Storage Commands
- `get_notes()`: Load all notes from storage
- `save_notes_command(notes)`: Save entire notes array
- `create_note()`: Create new empty note with UUID
- `update_note(note)`: Update existing note
- `delete_note(id)`: Delete note by UUID
- `get_storage_location()`: Get path to notes.json file

### Injection Commands
- `inject_text_command(text)`: Inject text into active window
- `get_clipboard_text()`: Get current clipboard content (debugging)

### Hotkey Commands
- `register_custom_hotkey(shortcut, action)`: Register custom hotkey (placeholder)

## Building

### Prerequisites
- Rust 1.70+
- Node.js 18+
- Windows 10/11 SDK

### Development
```bash
cargo tauri dev
```

### Production Build
```bash
cargo tauri build
```

This creates a single NSIS installer in `src-tauri/target/release/bundle/nsis/`

## Portable Mode

To enable portable mode, either:
1. Create an empty `.portable` file next to the executable
2. Create a `data/` folder next to the executable

In portable mode, `notes.json` will be stored in the `data/` folder next to the exe instead of AppData.

## Dependencies

- **tauri 2.0**: Main framework with tray-icon and global-shortcut features
- **serde/serde_json**: JSON serialization
- **dirs**: Cross-platform directory paths
- **uuid**: UUID generation (v4)
- **chrono**: Timestamp handling
- **windows**: Win32 API bindings for text injection

## Architecture

```
src-tauri/
├── Cargo.toml          # Rust dependencies
├── tauri.conf.json     # Tauri configuration
├── build.rs            # Build script
├── capabilities/       # Tauri v2 permissions
│   └── default.json
└── src/
    ├── main.rs         # App entry, tray menu, window management
    ├── lib.rs          # Module declarations
    ├── storage.rs      # Notes storage and persistence
    ├── hotkeys.rs      # Global keyboard shortcuts
    └── injection.rs    # Text injection via Win32 API
```

## Notes on Tauri v2

This backend uses Tauri v2 which has breaking changes from v1:
- New window API: `get_webview_window()` instead of `get_window()`
- Tray icon API completely redesigned
- Capabilities system for permissions
- Plugin architecture for global shortcuts
