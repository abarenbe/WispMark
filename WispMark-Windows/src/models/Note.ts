export interface Note {
  id: string; // UUID
  content: string;
  createdAt: string; // ISO date
  modifiedAt: string; // ISO date
  isPinned: boolean;
}

export interface NoteWithComputed extends Note {
  title: string;
  preview: string;
  tags: string[];
}

// Extract the title from note content (first non-empty line)
export function getNoteTitle(content: string): string {
  const lines = content.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed) {
      // Remove markdown formatting from title
      return trimmed
        .replace(/^#+\s+/, '') // Remove heading markers
        .replace(/\*\*(.+?)\*\*/g, '$1') // Remove bold
        .replace(/\*(.+?)\*/g, '$1') // Remove italic
        .replace(/\[(.+?)\]\(.+?\)/g, '$1') // Remove links, keep text
        .replace(/\[\[(.+?)\]\]/g, '$1') // Remove wiki links
        .substring(0, 100); // Limit length
    }
  }
  return 'Untitled';
}

// Extract a preview from note content (first few lines, ~100 chars)
export function getNotePreview(content: string): string {
  const lines = content.split('\n');
  let preview = '';

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed) {
      preview += trimmed + ' ';
      if (preview.length >= 100) break;
    }
  }

  return preview.substring(0, 100).trim() + (preview.length > 100 ? '...' : '');
}

// Extract tags from note content (#tag format)
export function getNoteTags(content: string): string[] {
  const tagRegex = /#([a-zA-Z0-9_-]+)/g;
  const tags = new Set<string>();
  let match;

  while ((match = tagRegex.exec(content)) !== null) {
    tags.add(match[1]);
  }

  return Array.from(tags);
}

// Add computed properties to a note
export function enrichNote(note: Note): NoteWithComputed {
  return {
    ...note,
    title: getNoteTitle(note.content),
    preview: getNotePreview(note.content),
    tags: getNoteTags(note.content),
  };
}
