# FloatMD Windows - Quick Start Guide

## Prerequisites

1. **Rust** (1.70 or later)
   ```bash
   # Install from https://rustup.rs/
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Node.js** (18 or later)
   ```bash
   # Install from https://nodejs.org/
   # Or use nvm: nvm install 18
   ```

3. **Windows Build Tools**
   - Visual Studio 2022 with "Desktop development with C++" workload
   - Or Windows 10/11 SDK

## Setup

1. **Navigate to the Windows project directory:**
   ```bash
   cd FloatMD-Windows
   ```

2. **Install frontend dependencies:**
   ```bash
   npm install
   ```

3. **Install Rust dependencies** (automatic on first build)

## Development

**Run in development mode:**
```bash
npm run tauri dev
```

This will:
- Start the frontend dev server (Vite)
- Compile the Rust backend
- Launch the app with hot-reload enabled

**Development features:**
- Frontend changes hot-reload automatically
- Rust changes require app restart (automatic)
- Console logs visible in terminal

## Building for Production

**Create production build:**
```bash
npm run tauri build
```

This creates:
- **NSIS Installer**: `src-tauri/target/release/bundle/nsis/FloatMD_1.0.0_x64-setup.exe`
- **Portable EXE**: `src-tauri/target/release/FloatMD.exe`

## Project Structure

```
FloatMD-Windows/
├── src/                    # Frontend source (React/Vue/Svelte)
├── src-tauri/             # Rust backend
│   ├── src/
│   │   ├── main.rs        # Entry point, tray, window management
│   │   ├── storage.rs     # Notes storage & persistence
│   │   ├── hotkeys.rs     # Global keyboard shortcuts
│   │   └── injection.rs   # Text injection (Win32 API)
│   ├── Cargo.toml         # Rust dependencies
│   └── tauri.conf.json    # Tauri configuration
└── package.json           # Frontend dependencies
```

## Adding Icons

Before building, add icons to `src-tauri/icons/`:
- `icon.ico` - Windows icon (required)
- `32x32.png`, `128x128.png`, `128x128@2x.png`

See `src-tauri/icons/README.md` for generation instructions.

## Testing Portable Mode

1. Build the app: `npm run tauri build`
2. Copy the exe from `target/release/FloatMD.exe` to a test folder
3. Create a `.portable` file in the same folder:
   ```bash
   # In the folder with FloatMD.exe:
   echo. > .portable
   ```
4. Run the exe - it will create a `data/notes.json` file in the same folder

## Common Issues

### "Failed to register shortcut"
- Another app is using Ctrl+Shift+M or Ctrl+Alt+I
- Close conflicting apps or modify hotkeys in `src-tauri/src/hotkeys.rs`

### "Failed to load notes"
- Check file permissions in AppData folder
- Try portable mode by creating `.portable` file

### Build errors
- Make sure Visual Studio C++ tools are installed
- Run `rustup update` to update Rust toolchain
- Clear cache: `cargo clean` then rebuild

## Debugging

**View Rust logs:**
```bash
# Development mode automatically shows logs
npm run tauri dev
```

**Debug frontend:**
- Open DevTools in the app (F12 or Ctrl+Shift+I)
- Console logs appear in DevTools

**Debug storage:**
```typescript
// In frontend console:
const path = await invoke('get_storage_location');
console.log('Notes file:', path);
```

## Next Steps

1. **Read API docs**: See `API.md` for all available commands
2. **Customize UI**: Edit frontend files in `src/`
3. **Modify hotkeys**: Edit `src-tauri/src/hotkeys.rs`
4. **Add features**: Extend Rust backend with new commands

## Helpful Links

- [Tauri Documentation](https://tauri.app/)
- [Tauri API Reference](https://tauri.app/reference/javascript/api/)
- [Rust Documentation](https://doc.rust-lang.org/)
