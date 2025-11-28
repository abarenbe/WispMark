# FloatMD Help

## Setup

### Enable Text Injection
To inject text into other apps using **Opt+Cmd+I**, you need to grant permissions:

1. **Input Monitoring**: Go to System Settings > Privacy & Security > Input Monitoring and add Terminal (or the app running FloatMD)

2. **Accessibility**: Go to System Settings > Privacy & Security > Accessibility and add Terminal (or the app running FloatMD)

After adding permissions, restart FloatMD.

## Using FloatMD

### Text Injection
Press **Opt+Cmd+I** anywhere to paste your current note's content into the focused app.

### Notes Management
- **+** button: Create a new blank note
- **List** button: Browse all notes
- **Pin** button: Pin a note to keep it at the top of the list
- Notes are auto-saved as you type
- Empty notes are automatically deleted when you switch away
- First line of text becomes the note title

### Wiki Links
Link between notes using double brackets:
```
[[Note Title]]
```
- Click a wiki link to navigate to that note (creates it if it doesn't exist)
- Type `[[` to get autocomplete suggestions of existing note titles
- Use arrow keys to navigate suggestions, Enter to select, Escape to dismiss
- When you change a note's title that other notes link to, you'll be prompted to update all backlinks automatically

### Tags
Add tags to organize your notes:
```
#project #todo #idea
```
- Tags are displayed as colored pills
- Type `#` to get autocomplete suggestions of existing tags
- Use arrow keys to navigate suggestions, Enter to select, Escape to dismiss
- Click a tag to search for all notes with that tag

### Markdown Formatting

FloatMD renders markdown as you type. Syntax markers hide when your cursor moves away.

#### Headings
```
# Heading 1
## Heading 2
### Heading 3
```

#### Text Styling
```
**bold text**
*italic text*
~~strikethrough~~
`inline code`
```

#### Lists
Unordered:
```
- Item one
- Item two
  - Sub-item (press Tab to indent)
```

Ordered:
```
1. First item
2. Second item
```

Press **Enter** to continue a list. Press **Tab** to indent, **Shift+Tab** to outdent.

#### Checkboxes
```
- [ ] Unchecked task
- [x] Completed task
```
Click checkboxes to toggle them.

#### Other
```
> Blockquote text

--- (horizontal rule)

[Link text](https://url.com)
```

## Keyboard Shortcuts
| Action | Shortcut |
|--------|----------|
| Inject text | Opt+Cmd+I |
| Indent list | Tab |
| Outdent list | Shift+Tab |
| Continue list | Enter |
| Accept autocomplete | Enter |
| Navigate autocomplete | ↑ / ↓ |
| Dismiss autocomplete | Escape |
