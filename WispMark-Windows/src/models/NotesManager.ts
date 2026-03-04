import { invoke } from '@tauri-apps/api/core';
import { v4 as uuidv4 } from 'uuid';
import { Note, NoteWithComputed, enrichNote, getNoteTitle } from './Note';

export class NotesManager {
  // Load notes from backend
  static async loadNotes(): Promise<Note[]> {
    try {
      const notes = await invoke<Note[]>('load_notes');
      return notes;
    } catch (error) {
      console.error('Failed to load notes:', error);
      return [];
    }
  }

  // Save notes to backend
  static async saveNotes(notes: Note[]): Promise<void> {
    try {
      await invoke('save_notes', { notes });
    } catch (error) {
      console.error('Failed to save notes:', error);
      throw error;
    }
  }

  // Create a new note
  static createNote(content: string = ''): Note {
    const now = new Date().toISOString();
    return {
      id: uuidv4(),
      content,
      createdAt: now,
      modifiedAt: now,
      isPinned: false,
    };
  }

  // Update an existing note
  static updateNote(note: Note, updates: Partial<Note>): Note {
    return {
      ...note,
      ...updates,
      modifiedAt: new Date().toISOString(),
    };
  }

  // Delete a note from the array
  static deleteNote(notes: Note[], noteId: string): Note[] {
    return notes.filter(n => n.id !== noteId);
  }

  // Search notes by query
  static searchNotes(notes: Note[], query: string): NoteWithComputed[] {
    if (!query.trim()) {
      return notes.map(enrichNote);
    }

    const lowerQuery = query.toLowerCase();

    return notes
      .map(enrichNote)
      .filter(note => {
        // Search in content, title, and tags
        return (
          note.content.toLowerCase().includes(lowerQuery) ||
          note.title.toLowerCase().includes(lowerQuery) ||
          note.tags.some(tag => tag.toLowerCase().includes(lowerQuery))
        );
      });
  }

  // Get note by title (for wiki links)
  static getNoteByTitle(notes: Note[], title: string): Note | undefined {
    return notes.find(note => {
      const noteTitle = getNoteTitle(note.content);
      return noteTitle.toLowerCase() === title.toLowerCase();
    });
  }

  // Sort notes (pinned first, then by modified date)
  static sortNotes(notes: NoteWithComputed[]): NoteWithComputed[] {
    return [...notes].sort((a, b) => {
      // Pinned notes first
      if (a.isPinned !== b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      // Then by modified date (newest first)
      return new Date(b.modifiedAt).getTime() - new Date(a.modifiedAt).getTime();
    });
  }

  // Get all unique tags from notes
  static getAllTags(notes: Note[]): string[] {
    const tags = new Set<string>();
    notes.forEach(note => {
      const noteTags = enrichNote(note).tags;
      noteTags.forEach(tag => tags.add(tag));
    });
    return Array.from(tags).sort();
  }
}
