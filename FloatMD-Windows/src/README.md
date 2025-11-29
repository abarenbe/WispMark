# FloatMD-Windows Source Code

This directory contains the TypeScript/React implementation of FloatMD for Windows.

## Project Structure

```
src/
├── types/           # TypeScript type definitions
├── utils/           # Utility functions for markdown and wiki links
├── components/      # React components
├── hooks/           # Custom React hooks
└── README.md        # This file
```

## Types (`types/index.ts`)

Core TypeScript interfaces and types used throughout the application:

- **Note**: Main note data structure
- **TokenType**: Markdown token types for syntax highlighting
- **MarkdownToken**: Parsed markdown token with metadata
- **AutocompletePosition**: Position coordinates for autocomplete popup
- **TriggerType**: Type of autocomplete trigger ('wikilink' | 'tag')

## Utilities

### Markdown Utils (`utils/markdown.ts`)

Markdown parsing and processing utilities:

- **extractTitle(content: string): string**
  - Extracts the title from markdown content (first non-empty line)
  - Strips heading markers (#) if present
  - Returns 'Untitled' if no content found

- **extractTags(content: string): string[]**
  - Finds all tags matching the pattern `#tagname`
  - Pattern: `#[a-zA-Z][a-zA-Z0-9_-]*`
  - Returns sorted array of unique tags (lowercase)

- **extractWikiLinks(content: string): string[]**
  - Finds all wiki links matching the pattern `[[Title]]`
  - Returns array of unique link targets

- **getPreview(content: string, maxLength: number): string**
  - Generates a clean preview of markdown content
  - Strips markdown syntax (bold, italic, code, links, etc.)
  - Skips the title line
  - Default max length: 100 characters

- **parseMarkdown(content: string): MarkdownToken[]**
  - Tokenizes markdown content for syntax highlighting
  - Supports: headings, bold, italic, code, code blocks, links, wiki links, tags, checkboxes, blockquotes, list items
  - Returns array of tokens with type and content

### Wiki Links Utils (`utils/wikilinks.ts`)

Wiki link management and backlink handling:

- **findNoteByTitle(notes: Note[], title: string): Note | undefined**
  - Finds a note by its title (case-insensitive)

- **getBacklinks(notes: Note[], noteTitle: string): Note[]**
  - Finds all notes that link to the specified note
  - Returns array of notes containing wiki links to the target

- **updateBacklinks(notes: Note[], oldTitle: string, newTitle: string): Note[]**
  - Updates all wiki links when a note's title changes
  - Returns new array of notes with updated content
  - Automatically updates modifiedAt timestamp

- **wikiLinkExists(notes: Note[], title: string): boolean**
  - Checks if a wiki link target exists in the notes

- **getWikiLinkTargets(note: Note): string[]**
  - Gets all unique wiki link targets from a note

- **getBrokenWikiLinks(notes: Note[], note: Note): string[]**
  - Finds broken wiki links (links to notes that don't exist)

## Components

### Autocomplete (`components/Autocomplete.tsx`)

Autocomplete popup for wiki links and tags:

**Props:**
- `suggestions: string[]` - List of suggestions to display
- `onSelect: (suggestion: string) => void` - Callback when user selects a suggestion
- `position: AutocompletePosition` - Position to display the popup (x, y)
- `visible: boolean` - Whether the autocomplete is visible
- `triggerType?: TriggerType` - Type of trigger ('wikilink' | 'tag')
- `query?: string` - Current query string for filtering

**Features:**
- Keyboard navigation (Arrow Up/Down, Enter to select, Escape to close)
- Auto-filtering based on query
- Mouse hover selection
- Auto-scroll selected item into view
- Displays up to 10 suggestions
- Different styling for tags vs wiki links

### TagPill (`components/TagPill.tsx`)

Tag display component with optional remove button:

**Props:**
- `tag: string` - The tag name (without # symbol)
- `onClick?: (tag: string) => void` - Callback when tag is clicked
- `onRemove?: (tag: string) => void` - Callback when remove button is clicked
- `isRemovable?: boolean` - Whether to show remove button (default: false)
- `size?: 'small' | 'medium' | 'large'` - Size variant (default: 'medium')

**Features:**
- Clickable to filter/search by tag
- Optional remove button
- Three size variants
- Hover effects
- Themed colors (CSS variables)

## Hooks

### useAutocomplete (`hooks/useAutocomplete.ts`)

Custom hook for autocomplete logic with trigger detection:

**Options:**
- `notes: Note[]` - Array of all notes
- `editorRef: React.RefObject<HTMLTextAreaElement>` - Ref to the editor textarea

**Returns:**
- `showAutocomplete: boolean` - Whether to show autocomplete
- `suggestions: string[]` - Current suggestions based on trigger type
- `position: AutocompletePosition` - Position for autocomplete popup
- `triggerType: TriggerType | null` - Current trigger type ('wikilink' | 'tag')
- `query: string` - Current query string
- `handleSelect: (suggestion: string) => void` - Function to handle selection
- `hideAutocomplete: () => void` - Function to manually hide autocomplete

**Features:**
- Detects `[[` for wiki link autocomplete
- Detects `#` for tag autocomplete
- Automatically filters suggestions based on partial input
- Handles text insertion at correct cursor position
- Manages keyboard navigation state
- Auto-closes on arrow left/right

## Usage Examples

### Using Markdown Utils

```typescript
import { extractTitle, extractTags, extractWikiLinks, parseMarkdown } from './utils/markdown';

const content = `# My Note

This is a note about #typescript and #react.
Check out [[Other Note]] for more info.`;

const title = extractTitle(content); // "My Note"
const tags = extractTags(content); // ["react", "typescript"]
const links = extractWikiLinks(content); // ["Other Note"]
const tokens = parseMarkdown(content); // Array of MarkdownTokens
```

### Using Wiki Links Utils

```typescript
import { findNoteByTitle, getBacklinks, updateBacklinks } from './utils/wikilinks';

const notes: Note[] = [...];

// Find a note
const note = findNoteByTitle(notes, "My Note");

// Get backlinks
const backlinks = getBacklinks(notes, "My Note");

// Update wiki links when renaming
const updatedNotes = updateBacklinks(notes, "Old Title", "New Title");
```

### Using Components

```tsx
import { Autocomplete, TagPill } from './components';

// Autocomplete
<Autocomplete
  suggestions={['Note 1', 'Note 2', 'Note 3']}
  onSelect={(title) => console.log('Selected:', title)}
  position={{ x: 100, y: 200 }}
  visible={true}
  triggerType="wikilink"
  query="Note"
/>

// Tag Pill
<TagPill
  tag="typescript"
  onClick={(tag) => console.log('Clicked:', tag)}
  onRemove={(tag) => console.log('Remove:', tag)}
  isRemovable={true}
  size="medium"
/>
```

### Using useAutocomplete Hook

```tsx
import { useRef } from 'react';
import { useAutocomplete } from './hooks';
import { Autocomplete } from './components';

function Editor({ notes }: { notes: Note[] }) {
  const editorRef = useRef<HTMLTextAreaElement>(null);

  const {
    showAutocomplete,
    suggestions,
    position,
    triggerType,
    query,
    handleSelect,
  } = useAutocomplete({ notes, editorRef });

  return (
    <div>
      <textarea ref={editorRef} />

      {showAutocomplete && (
        <Autocomplete
          suggestions={suggestions}
          onSelect={handleSelect}
          position={position}
          visible={showAutocomplete}
          triggerType={triggerType || 'wikilink'}
          query={query}
        />
      )}
    </div>
  );
}
```

## CSS Variables

The components use CSS variables for theming. Define these in your global CSS:

```css
:root {
  /* Autocomplete */
  --background-secondary: #1e1e1e;
  --border-color: #3e3e3e;
  --selection-background: #2a2a2a;
  --text-primary: #ffffff;
  --link-color: #06b6d4;

  /* Tag Pill */
  --tag-background: rgba(34, 197, 94, 0.2);
  --tag-background-hover: rgba(34, 197, 94, 0.3);
  --tag-color: #22c55e;
}
```

## Notes

- All utilities are pure functions with no side effects
- Components use inline styles for maximum portability
- The autocomplete hook manages all editor interaction
- Wiki links are case-insensitive for matching
- Tags are automatically converted to lowercase
- The parser supports nested markdown elements
