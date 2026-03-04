# WispMark Windows Backend - Documentation Index

Welcome to the WispMark Windows Tauri backend! This index will help you navigate the documentation.

## Quick Navigation

### 🚀 Getting Started
Start here if you're new to the project:
1. **[QUICKSTART.md](QUICKSTART.md)** - Setup, build, and run the application
2. **[README.md](README.md)** - Overview of features and architecture

### 📚 For Frontend Developers
Building the UI? Read these:
1. **[API.md](API.md)** - Complete API reference for all Tauri commands and events
2. **[PLATFORM_COMPARISON.md](PLATFORM_COMPARISON.md)** - How Windows version compares to macOS

### 🔧 For Backend Developers
Working on the Rust backend? Read these:
1. **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Technical details of the implementation
2. Source code documentation (see File Structure below)

### 📦 Distribution
Preparing for release:
1. **[icons/README.md](icons/README.md)** - Icon generation instructions
2. **[.portable.example](.portable.example)** - Portable mode setup

---

## File Structure

```
src-tauri/
│
├── 📄 Documentation
│   ├── INDEX.md                    ← You are here
│   ├── README.md                   ← Project overview
│   ├── QUICKSTART.md               ← Setup and build guide
│   ├── API.md                      ← Frontend API reference
│   ├── PLATFORM_COMPARISON.md      ← macOS vs Windows comparison
│   └── IMPLEMENTATION_SUMMARY.md   ← Technical implementation details
│
├── 🦀 Rust Source Code
│   └── src/
│       ├── main.rs                 ← Entry point, tray menu, window management
│       ├── lib.rs                  ← Module declarations
│       ├── storage.rs              ← Note storage and persistence
│       ├── hotkeys.rs              ← Global keyboard shortcuts
│       └── injection.rs            ← Text injection (Win32 API)
│
├── ⚙️ Configuration
│   ├── Cargo.toml                  ← Rust dependencies
│   ├── tauri.conf.json             ← Tauri app configuration
│   ├── build.rs                    ← Build script
│   └── capabilities/
│       └── default.json            ← Tauri v2 permissions
│
├── 🎨 Assets
│   └── icons/
│       └── README.md               ← Icon generation guide
│
└── 🔧 Utilities
    ├── .gitignore                  ← Git ignore rules
    └── .portable.example           ← Portable mode marker template
```

---

## Documentation Purposes

| Document | Purpose | Target Audience |
|----------|---------|----------------|
| **INDEX.md** | Navigation hub | Everyone |
| **README.md** | Project overview, features | New developers |
| **QUICKSTART.md** | Setup and development workflow | Developers setting up |
| **API.md** | Tauri commands, events, types | Frontend developers |
| **PLATFORM_COMPARISON.md** | Design decisions, feature parity | Architects, contributors |
| **IMPLEMENTATION_SUMMARY.md** | Technical details, statistics | Backend developers, auditors |

---

## Source Code Overview

### main.rs (134 lines)
**Purpose:** Application entry point and core functionality

**Key Functions:**
- `create_tray_menu()` - System tray with menu items
- `main()` - Tauri builder, plugin setup, event handlers

**Features:**
- System tray icon with menu (New Note, Show/Hide, Quit)
- Window hide on close (prevents exit)
- Tauri command registration

**Read this to understand:** How the app initializes and manages the window lifecycle

---

### storage.rs (146 lines)
**Purpose:** Note storage and persistence

**Key Types:**
- `struct Note` - Note data model

**Key Functions:**
- `get_storage_path()` - Detects portable mode and returns storage location
- `load_notes()` - Reads notes.json
- `save_notes()` - Writes notes.json

**Tauri Commands:**
- `get_notes()` - Load all notes
- `save_notes_command()` - Save notes array
- `create_note()` - Create new note
- `update_note()` - Update existing note
- `delete_note()` - Delete note by ID
- `get_storage_location()` - Get storage path

**Read this to understand:** How notes are stored and retrieved, portable mode detection

---

### hotkeys.rs (60 lines)
**Purpose:** Global keyboard shortcut registration

**Key Functions:**
- `register_hotkeys()` - Register Ctrl+Shift+M and Ctrl+Alt+I
- `unregister_hotkeys()` - Cleanup on exit

**Shortcuts:**
- **Ctrl+Shift+M** - Toggle window visibility
- **Ctrl+Alt+I** - Emit inject-text-requested event

**Read this to understand:** How global hotkeys work, how to add new shortcuts

---

### injection.rs (175 lines)
**Purpose:** Text injection into active Windows application

**Key Functions:**
- `set_clipboard_text()` - Copy text to Windows clipboard (Win32)
- `simulate_ctrl_v()` - Simulate Ctrl+V keypress (SendInput)
- `inject_text()` - Main injection function

**Tauri Commands:**
- `inject_text_command()` - Inject text
- `get_clipboard_text()` - Get clipboard content (debugging)

**Win32 APIs Used:**
- OpenClipboard, EmptyClipboard, SetClipboardData, CloseClipboard
- GlobalAlloc, GlobalLock, GlobalUnlock, GlobalFree
- SendInput with INPUT_KEYBOARD

**Read this to understand:** How text injection works on Windows, Win32 API usage

---

### lib.rs (4 lines)
**Purpose:** Module declarations

Simple file that declares the three modules (storage, hotkeys, injection).

---

## Configuration Files

### Cargo.toml
Rust dependencies and project metadata.

**Key Dependencies:**
- tauri 2.0 - Main framework
- tauri-plugin-global-shortcut - Hotkey support
- serde/serde_json - JSON serialization
- uuid - Note IDs
- chrono - Timestamps
- windows - Win32 API (Windows only)

### tauri.conf.json
Tauri application configuration.

**Key Settings:**
- Window size: 400x600
- Bundle target: NSIS installer
- Tray icon enabled
- App identifier: com.floatmd.app

### capabilities/default.json
Tauri v2 permissions system.

**Granted Permissions:**
- Window show/hide/focus
- Event emit/listen
- Shell commands (open URLs)

---

## Development Workflow

### 1. First Time Setup
```bash
# Read QUICKSTART.md for detailed instructions
cd WispMark-Windows
npm install
npm run tauri dev
```

### 2. Making Changes

**Frontend Changes:**
- Edit files in `src/` (React/Vue/Svelte)
- Changes hot-reload automatically

**Backend Changes:**
- Edit files in `src-tauri/src/`
- App restarts automatically
- Add new Tauri commands to `main.rs` handler

### 3. Testing
```bash
# Development build with console
npm run tauri dev

# Test portable mode
npm run tauri build
# Then copy exe and create .portable file
```

### 4. Building for Release
```bash
# Read QUICKSTART.md for full instructions
npm run tauri build

# Output: src-tauri/target/release/bundle/nsis/FloatMD_1.0.0_x64-setup.exe
```

---

## Common Tasks

### Adding a New Tauri Command

1. **Write the function in appropriate module:**
   ```rust
   // In storage.rs
   #[tauri::command]
   pub fn my_new_command(param: String) -> Result<String, String> {
       Ok(format!("Hello, {}", param))
   }
   ```

2. **Add to main.rs:**
   ```rust
   use storage::{/* ... */ my_new_command};

   .invoke_handler(tauri::generate_handler![
       // ... existing commands ...
       my_new_command,
   ])
   ```

3. **Call from frontend:**
   ```typescript
   import { invoke } from '@tauri-apps/api/core';
   const result = await invoke<string>('my_new_command', { param: 'World' });
   ```

### Adding a New Global Shortcut

1. **Edit hotkeys.rs:**
   ```rust
   let my_shortcut = Shortcut::new(
       Some(Modifiers::CONTROL | Modifiers::SHIFT),
       Code::KeyN
   );

   app.global_shortcut().on_shortcut(my_shortcut, |app, _, _| {
       // Your handler code
   })?;
   ```

2. **Document in API.md**

### Modifying Window Behavior

1. **Edit tauri.conf.json for initial state:**
   ```json
   {
     "app": {
       "windows": [{
         "width": 500,  // Changed from 400
         "height": 700  // Changed from 600
       }]
     }
   }
   ```

2. **Edit main.rs for runtime behavior:**
   ```rust
   .on_window_event(|window, event| {
       // Add new event handlers
   })
   ```

---

## API Quick Reference

### Most Common Commands

```typescript
// Load all notes
const notes = await invoke<Note[]>('get_notes');

// Create new note
const note = await invoke<Note>('create_note');

// Save note
await invoke('update_note', { note: updatedNote });

// Delete note
await invoke('delete_note', { id: noteId });

// Inject text
await invoke('inject_text_command', { text: noteContent });

// Get storage path
const path = await invoke<string>('get_storage_location');
```

### Most Common Events

```typescript
// Listen for inject hotkey
await listen('inject-text-requested', () => {
    // Handle injection
});

// Listen for new note from tray
await listen('create-new-note', () => {
    // Create and display new note
});
```

---

## Troubleshooting

| Issue | Document to Check |
|-------|-------------------|
| Build errors | QUICKSTART.md |
| API usage questions | API.md |
| Hotkey not working | hotkeys.rs comments |
| Text injection fails | injection.rs comments |
| Notes not saving | storage.rs comments |
| Platform differences | PLATFORM_COMPARISON.md |

---

## External Resources

- **Tauri Documentation:** https://tauri.app/
- **Tauri API Reference:** https://tauri.app/reference/javascript/api/
- **Rust Book:** https://doc.rust-lang.org/book/
- **Windows API Reference:** https://learn.microsoft.com/en-us/windows/win32/

---

## Statistics

- **Total Files Created:** 17
- **Rust Source Files:** 5 (519 lines)
- **Documentation Files:** 6 (this + 5 others)
- **Configuration Files:** 4
- **Tauri Commands:** 9
- **Global Shortcuts:** 2
- **System Tray Menu Items:** 4

---

## Next Steps

1. ✅ Backend Complete - You are here
2. 🔲 Create Frontend (React/Vue/Svelte)
3. 🔲 Generate Icons (see icons/README.md)
4. 🔲 Test All Features
5. 🔲 Build Release Installer
6. 🔲 Distribute to Users

---

**The Tauri Rust backend is complete and production-ready!**

Start with **QUICKSTART.md** to begin development, or **API.md** if you're building the frontend.
