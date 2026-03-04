# WispMark Workspaces Feature Plan

## Overview

Add a workspace system (`@workspace`) for contextual note organization, alongside a new bottom metadata bar for both workspaces and tags.

## Core Concepts

### Workspaces vs Tags

| Aspect | Tags (`#tag`) | Workspaces (`@workspace`) |
|--------|---------------|---------------------------|
| Inheritance | None - explicit only | Auto-inherit from current context |
| Hierarchy | Flat | Nested (`@work/project/sprint`) |
| Context mode | Filter (additive) | "In" mode (subtractive view) |
| Default | None | Inherits active workspace |
| Global escape | N/A | `@.` = visible everywhere |

### Workspace Assignment Rules

- **No `@` assignment**: Shown only in home view (no workspace active)
- **`@.`**: Explicitly global - visible in ALL views (e.g., todo list)
- **`@workspace`**: Visible when "in" that workspace or its parent
- **Multiple workspaces**: Additive - note in `@work` AND `@personal` shows in both
- **Auto-inheritance**: New notes created while "in" `@work` automatically get `@work`

### View Behavior

**Home view (no workspace active):**
- Shows: uncategorized notes (no `@`) + `@.` global notes
- Workspaces displayed as collapsed groups

**Workspace view (e.g., "in" `@work`):**
- Shows: `@work` + all `@work/*` children + `@.` global notes
- Does NOT show: uncategorized or other workspaces (`@personal`)

---

## Data Model Changes

### Note Struct

```swift
struct Note: Codable, Identifiable {
    var id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var workspaces: Set<String>  // NEW: ["work", "work/projectX", "."]
    var tags: Set<String>        // NEW: explicit tags (migrate from parsed)
}
```

### NotesManager

```swift
class NotesManager {
    // Existing
    var notes: [Note]
    var activeNoteId: UUID?

    // NEW
    var activeWorkspace: String?  // nil = home, "." = global, "work" = in workspace

    // NEW methods
    func notesForCurrentView() -> [Note]
    func setActiveWorkspace(_ workspace: String?)
    func getAllWorkspaces() -> [String]  // sorted, hierarchical
    func addWorkspace(to note: Note, workspace: String)
    func removeWorkspace(from note: Note, workspace: String)
}
```

### Storage

- UserDefaults key unchanged (`floatmd_notes`)
- Add `floatmd_active_workspace` for persistence across sessions
- Migration: existing notes get empty `workspaces: []` and `tags` populated from parsed content

---

## UI Components

### 1. Bottom Metadata Bar (NEW)

Add below text editor, above any existing footer:

```
┌─────────────────────────────────────────────────┐
│ Note content...                                 │
│                                                 │
├─────────────────────────────────────────────────┤
│ #project #urgent     @work/clientA @.       +   │
└─────────────────────────────────────────────────┘
```

**Behavior:**
- Left side: tag pills (clickable to remove)
- Right side: workspace pills (clickable to remove)
- `+` button: opens unified autocomplete for both `#` and `@`
- Pills use existing theme colors (`tagPill`, `workspaceTag`)

**Implementation:** `MetadataBarView: NSView`
- Horizontal stack of pill buttons
- Click pill → remove from note
- Click `+` → show `MetadataAutocompleteView`

### 2. Active Workspace Indicator in Title Bar

**Critical UX element**: Clear visual indication when "in" a workspace.

**Adaptive display based on available space:**

```
Full width (plenty of room):
┌─────────────────────────────────────────────────┐
│ [@work/clientA]  Note Title Here             + │
└─────────────────────────────────────────────────┘

Medium width (title getting cramped):
┌───────────────────────────────────┐
│ [@work]  Note Title Here       + │
└───────────────────────────────────┘

Narrow width (compact mode):
┌─────────────────────────┐
│ ●  Note Title Here   + │  ← colored dot only
└─────────────────────────┘
```

**Adaptive behavior:**
1. **Full pill**: `[@work/clientA]` - shows full workspace path
2. **Truncated pill**: `[@work]` - shows root workspace only when space is tight
3. **Colored dot**: `●` - minimal indicator when very cramped, uses `workspaceTag` theme color

**Implementation:**
- Calculate available width after title text
- If `< 100px` available → colored dot only
- If `< 200px` available → root workspace only
- Otherwise → full workspace path

**Interactions:**
- Click pill/dot → open workspace picker to switch or exit to home
- Hover on dot → tooltip shows full workspace path
- Hidden entirely when `activeWorkspace == nil` (home view)

**Color coding:**
- Pill background: `workspaceTagBackground` from theme
- Pill text: `workspaceTag` from theme
- Dot: solid `workspaceTag` color
- Distinct from note's workspace assignments in bottom bar

### 3. NoteBrowserView Changes

**When in home view:**
```
┌─────────────────────────────────┐
│ 🔍 Search...                    │
├─────────────────────────────────┤
│ 📌 Pinned Note                  │
│ Regular Note                    │
│ Another Note                    │
├─────────────────────────────────┤
│ 📁 @work (5)              ▶     │
│ 📁 @personal (3)          ▶     │
│ 📁 @. global (2)          ▶     │
└─────────────────────────────────┘
```

- Uncategorized notes shown at top
- Workspaces shown as collapsed rows with note count
- Click workspace row → enter that workspace

**When in workspace:**
```
┌─────────────────────────────────┐
│ ← @work/clientA                 │
│ 🔍 Search...                    │
├─────────────────────────────────┤
│ 📌 Pinned Client Note           │
│ Client Meeting Notes            │
│ @. Todo List (global)           │
├─────────────────────────────────┤
│ 📁 @work/clientA/sprint1 (2) ▶  │
└─────────────────────────────────┘
```

- Back button/breadcrumb to exit workspace
- Shows workspace notes + `@.` global notes
- Child workspaces shown as expandable

### 4. Autocomplete Enhancement

**In-content autocomplete:**
- `#` triggers tag autocomplete (existing, keep working)
- `@` triggers workspace autocomplete (NEW)
- Selecting from autocomplete adds to note's metadata (not just text)

**MetadataAutocompleteView (for bottom bar `+`):**
- Combined list: recent tags, recent workspaces
- Type `#` to filter tags, `@` to filter workspaces
- Create new tag/workspace inline

### 5. Multi-select for Bulk Assignment

In NoteBrowserView:
- Hold Cmd+click to multi-select notes
- Right-click → "Add to workspace..." submenu
- Or drag-drop onto workspace row

---

## Implementation Steps

### Phase 1: Data Model & Storage
1. Update `Note` struct with `workspaces: Set<String>` and `tags: Set<String>`
2. Add migration logic for existing notes (parse tags from content → `tags` field)
3. Add `activeWorkspace` to NotesManager
4. Update save/load for new fields
5. Add workspace-aware filtering: `notesForCurrentView()`

### Phase 2: Bottom Metadata Bar
1. Create `MetadataBarView` class
2. Implement pill rendering for tags and workspaces
3. Add click-to-remove behavior
4. Add `+` button with autocomplete popup
5. Integrate into MainView layout (below editor)
6. Move character count to title bar or metadata bar corner

### Phase 3: Workspace Context Mode
1. Add workspace pill to title bar header
2. Implement workspace switching in NoteBrowserView
3. Add collapsed workspace rows in home view
4. Add back navigation when in workspace
5. Implement auto-inheritance for new notes

### Phase 4: Autocomplete for `@`
1. Add `WorkspaceAutocompleteView` (similar to `TagAutocompleteView`)
2. Trigger on `@` character in editor
3. Hook selection to add workspace to note metadata
4. Update `MetadataAutocompleteView` for combined picker

### Phase 5: Polish & Edge Cases
1. Handle workspace renaming (update all notes)
2. Handle workspace deletion (prompt to reassign/remove)
3. Search behavior: always global, boost current workspace matches
4. Status bar menu: show workspace context
5. Keyboard shortcuts: Cmd+Shift+W to switch workspace?

---

## Key Files to Modify

**macOS (`main.swift`):**
- Line ~5: `Note` struct - add fields
- Line ~39: `NotesManager` - add workspace logic
- Line ~843: `MainView` - add MetadataBarView
- Line ~663: `FloatingPanel` - layout adjustments
- Line ~2870: `NoteBrowserView` - workspace grouping/navigation
- Line ~2200: `TagAutocompleteView` - extend or duplicate for workspaces
- Line ~500: Theme colors (already has `workspaceTag` colors)

**Windows (`WispMark-Windows/`):**
- `src/models/Note.ts` - add fields
- `src/models/NotesManager.ts` - add workspace logic
- `src/App.tsx` - layout for metadata bar
- `src/components/NotesList.tsx` - workspace grouping
- `src-tauri/src/storage.rs` - persistence

**iOS (`WispMark-iOS/`):**
- `Models/Note.swift` - add fields
- `Models/NotesManager.swift` - add workspace logic
- Views for metadata bar and workspace navigation

---

## Migration Strategy

1. On first load with new version:
   - Parse existing notes for `#tags` → populate `tags` field
   - Set `workspaces: []` for all existing notes
   - Existing notes remain visible in home view (uncategorized)

2. No breaking changes:
   - `#tag` in content still works (hybrid: parsed + explicit)
   - Notes without workspaces work as before

---

## Open Questions (Resolved)

- ✅ Storage: Separate property (not in content)
- ✅ Hierarchy: Unlimited nesting
- ✅ Multiplicity: Multiple workspaces per note (additive)
- ✅ Default: Auto-inherit current workspace
- ✅ Global: `@.` for "pinned everywhere" notes
- ✅ Uncategorized: No `@` = shown in home view only
- ✅ Tags in bar: Yes, both tags and workspaces
- ✅ In-content autocomplete: Yes, `@` triggers workspace autocomplete
