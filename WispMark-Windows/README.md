# WispMark Windows Frontend

React TypeScript frontend for WispMark - a floating markdown note-taking app for Windows.

## Features

- **Rich Markdown Editor**: Clean, distraction-free editing experience
- **Notes Management**: Create, edit, delete, and pin notes
- **Search**: Quick search across all notes and tags
- **Themes**: 5 beautiful themes (Dark, Light, Nord, Solarized, Sepia)
- **Tags**: Auto-extracted from `#tag` syntax
- **Wiki Links**: Support for `[[Note Title]]` linking
- **Auto-save**: Changes are automatically saved as you type

## Tech Stack

- **React 18** with TypeScript
- **Vite** for fast development and building
- **Tauri v2** for native Windows integration
- **CSS3** with theming support

## Project Structure

```
WispMark-Windows/
├── src/
│   ├── components/
│   │   ├── Editor.tsx          # Markdown editor component
│   │   ├── NotesList.tsx       # Sidebar with notes list
│   │   └── Settings.tsx        # Settings panel
│   ├── models/
│   │   ├── Note.ts             # Note interface and utilities
│   │   └── NotesManager.ts     # Notes CRUD operations
│   ├── styles/
│   │   └── App.css             # Global styles
│   ├── themes/
│   │   └── index.ts            # Theme definitions
│   ├── App.tsx                 # Main app component
│   └── main.tsx                # React entry point
├── index.html                  # HTML entry point
├── package.json                # Dependencies
├── tsconfig.json               # TypeScript config
└── vite.config.ts              # Vite config
```

## Installation

```bash
npm install
```

## Development

```bash
npm run dev
```

This will start the Vite development server on `http://localhost:1420`.

## Building

```bash
npm run build
```

This will compile TypeScript and build the production bundle to `dist/`.

## Integration with Tauri

This frontend is designed to work with a Tauri v2 backend. The backend should implement the following commands:

- `load_notes()`: Load all notes from storage
- `save_notes(notes)`: Save notes to storage
- `load_settings()`: Load app settings
- `save_settings(settings)`: Save app settings

## Keyboard Shortcuts

- `Ctrl+N`: Create new note
- `Ctrl+F`: Focus search
- `Ctrl+,`: Open settings
- `Ctrl+Shift+Space`: Toggle window visibility (handled by Tauri backend)

## Themes

The app includes 5 professionally designed themes:

1. **Dark**: High contrast dark theme
2. **Light**: Clean light theme
3. **Nord**: Arctic-inspired color palette
4. **Solarized**: Popular precision color theme
5. **Sepia**: Warm, vintage paper aesthetic

## License

MIT
