# FloatMD Tauri Backend API Documentation

This document describes the Tauri commands and events available to the frontend.

## Commands

Commands are invoked from the frontend using Tauri's `invoke()` function.

### Storage Commands

#### `get_notes()`
Load all notes from storage.

**Returns:** `Promise<Note[]>`

**Example:**
```typescript
import { invoke } from '@tauri-apps/api/core';

const notes = await invoke<Note[]>('get_notes');
```

---

#### `save_notes_command(notes)`
Save the entire notes array to storage.

**Parameters:**
- `notes: Note[]` - Array of notes to save

**Returns:** `Promise<void>`

**Example:**
```typescript
await invoke('save_notes_command', { notes: notesArray });
```

---

#### `create_note()`
Create a new empty note with a UUID.

**Returns:** `Promise<Note>`

**Example:**
```typescript
const newNote = await invoke<Note>('create_note');
```

---

#### `update_note(note)`
Update an existing note in storage.

**Parameters:**
- `note: Note` - The note object to update (must have existing ID)

**Returns:** `Promise<void>`

**Example:**
```typescript
await invoke('update_note', { note: updatedNote });
```

---

#### `delete_note(id)`
Delete a note by its UUID.

**Parameters:**
- `id: string` - UUID of the note to delete

**Returns:** `Promise<void>`

**Example:**
```typescript
await invoke('delete_note', { id: noteId });
```

---

#### `get_storage_location()`
Get the file path where notes.json is stored.

**Returns:** `Promise<string>`

**Example:**
```typescript
const path = await invoke<string>('get_storage_location');
console.log('Notes stored at:', path);
```

---

### Injection Commands

#### `inject_text_command(text)`
Inject text into the currently focused application using clipboard + Ctrl+V.

**Parameters:**
- `text: string` - The text to inject

**Returns:** `Promise<void>`

**Example:**
```typescript
await invoke('inject_text_command', { text: selectedNote.content });
```

**Note:** The FloatMD window should be hidden before calling this to ensure the target application is focused.

---

#### `get_clipboard_text()`
Get the current clipboard text (useful for debugging).

**Returns:** `Promise<string>`

**Example:**
```typescript
const clipboardContent = await invoke<string>('get_clipboard_text');
```

---

## Events

Events are emitted from the backend and can be listened to using Tauri's event system.

### `inject-text-requested`
Emitted when the user presses Ctrl+Alt+I hotkey.

**Payload:** `void`

**Example:**
```typescript
import { listen } from '@tauri-apps/api/event';

await listen('inject-text-requested', async () => {
  const currentNote = getCurrentNote();
  if (currentNote) {
    // Hide window first
    await window.hide();

    // Small delay to ensure target app is focused
    await new Promise(resolve => setTimeout(resolve, 100));

    // Inject text
    await invoke('inject_text_command', { text: currentNote.content });
  }
});
```

---

### `create-new-note`
Emitted when user clicks "New Note" in the system tray menu.

**Payload:** `void`

**Example:**
```typescript
await listen('create-new-note', async () => {
  const newNote = await invoke<Note>('create_note');
  addNoteToList(newNote);
  setCurrentNote(newNote);
});
```

---

## Data Types

### Note
```typescript
interface Note {
  id: string;           // UUID v4
  content: string;      // Markdown content
  createdAt: string;    // ISO 8601 timestamp
  modifiedAt: string;   // ISO 8601 timestamp
  isPinned: boolean;    // Pin status
}
```

**Note:** The Rust backend uses `created_at` and `modified_at` (snake_case) but serializes to `createdAt` and `modifiedAt` (camelCase) for JavaScript.

---

## Window Management

The backend automatically handles:
- **System Tray**: Show/Hide, New Note, Quit
- **Close Button**: Hides window instead of closing app
- **Ctrl+Shift+M**: Toggle window visibility
- **Ctrl+Alt+I**: Inject text hotkey

To manually control the window from frontend:

```typescript
import { getCurrentWindow } from '@tauri-apps/api/window';

const window = getCurrentWindow();

// Show window
await window.show();
await window.setFocus();

// Hide window
await window.hide();

// Check if visible
const isVisible = await window.isVisible();
```

---

## Portable Mode

The backend automatically detects portable mode by checking for:
1. `.portable` file next to executable
2. `data/` folder next to executable

If either exists, notes are stored in `data/notes.json` next to the exe.
Otherwise, notes are stored in `%APPDATA%/FloatMD/notes.json`.

Users don't need to configure this - it's automatic.

---

## Error Handling

All commands return `Promise` types. Errors should be caught:

```typescript
try {
  const notes = await invoke<Note[]>('get_notes');
} catch (error) {
  console.error('Failed to load notes:', error);
  // Show error message to user
}
```

---

## Best Practices

1. **Save Notes Frequently**: Call `save_notes_command()` after any modification
2. **Hide Before Inject**: Always hide the window before injecting text
3. **Update modifiedAt**: Update the `modifiedAt` timestamp when modifying notes
4. **Handle Errors**: Wrap all `invoke()` calls in try-catch blocks
5. **Listen to Events**: Set up event listeners on app startup

---

## Example: Complete Note Workflow

```typescript
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';

// Load notes on startup
async function loadNotes() {
  try {
    const notes = await invoke<Note[]>('get_notes');
    return notes;
  } catch (error) {
    console.error('Failed to load notes:', error);
    return [];
  }
}

// Create new note
async function createNote() {
  const note = await invoke<Note>('create_note');
  return note;
}

// Save note
async function saveNote(note: Note) {
  note.modifiedAt = new Date().toISOString();
  await invoke('update_note', { note });
}

// Delete note
async function deleteNote(id: string) {
  await invoke('delete_note', { id });
}

// Inject note into active app
async function injectNote(note: Note) {
  const window = getCurrentWindow();
  await window.hide();
  await new Promise(resolve => setTimeout(resolve, 100));
  await invoke('inject_text_command', { text: note.content });
}

// Listen for hotkeys
async function setupListeners() {
  await listen('inject-text-requested', async () => {
    const currentNote = getCurrentNote();
    if (currentNote) {
      await injectNote(currentNote);
    }
  });

  await listen('create-new-note', async () => {
    const note = await createNote();
    addNoteToUI(note);
  });
}

// Initialize app
async function init() {
  await setupListeners();
  const notes = await loadNotes();
  renderNotes(notes);
}

init();
```
