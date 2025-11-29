import { Note } from '../types';
import { extractTitle, extractWikiLinks } from './markdown';

/**
 * Find a note by its title
 */
export function findNoteByTitle(notes: Note[], title: string): Note | undefined {
  const normalizedTitle = title.trim().toLowerCase();
  return notes.find(note => {
    const noteTitle = extractTitle(note.content).toLowerCase();
    return noteTitle === normalizedTitle;
  });
}

/**
 * Get all notes that link to the specified note (backlinks)
 */
export function getBacklinks(notes: Note[], noteTitle: string): Note[] {
  const normalizedTitle = noteTitle.trim().toLowerCase();
  const backlinks: Note[] = [];

  for (const note of notes) {
    const wikiLinks = extractWikiLinks(note.content);
    const hasLink = wikiLinks.some(
      link => link.trim().toLowerCase() === normalizedTitle
    );

    if (hasLink) {
      backlinks.push(note);
    }
  }

  return backlinks;
}

/**
 * Update all wiki links when a note's title changes
 * Returns a new array of notes with updated content
 */
export function updateBacklinks(
  notes: Note[],
  oldTitle: string,
  newTitle: string
): Note[] {
  if (oldTitle.trim() === newTitle.trim()) {
    return notes;
  }

  const normalizedOldTitle = oldTitle.trim().toLowerCase();
  const updatedNotes: Note[] = [];

  for (const note of notes) {
    const wikiLinks = extractWikiLinks(note.content);
    const hasOldLink = wikiLinks.some(
      link => link.trim().toLowerCase() === normalizedOldTitle
    );

    if (!hasOldLink) {
      updatedNotes.push(note);
      continue;
    }

    // Update the content by replacing old wiki links with new ones
    let updatedContent = note.content;

    // Find and replace all instances of [[oldTitle]] with [[newTitle]]
    // Case-insensitive search but preserve the original case in replacement
    const pattern = new RegExp(
      `\\[\\[${escapeRegExp(oldTitle)}\\]\\]`,
      'gi'
    );
    updatedContent = updatedContent.replace(pattern, `[[${newTitle}]]`);

    updatedNotes.push({
      ...note,
      content: updatedContent,
      modifiedAt: new Date(),
    });
  }

  return updatedNotes;
}

/**
 * Check if a wiki link target exists in the notes
 */
export function wikiLinkExists(notes: Note[], title: string): boolean {
  return findNoteByTitle(notes, title) !== undefined;
}

/**
 * Get all unique wiki link targets from a note
 */
export function getWikiLinkTargets(note: Note): string[] {
  return extractWikiLinks(note.content);
}

/**
 * Get all broken wiki links (links to notes that don't exist)
 */
export function getBrokenWikiLinks(notes: Note[], note: Note): string[] {
  const wikiLinks = extractWikiLinks(note.content);
  return wikiLinks.filter(link => !wikiLinkExists(notes, link));
}

/**
 * Escape special regex characters
 */
function escapeRegExp(string: string): string {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
