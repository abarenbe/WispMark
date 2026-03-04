import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Note, NoteWithComputed, enrichNote } from './models/Note';
import { NotesManager } from './models/NotesManager';
import { Editor } from './components/Editor';
import { NotesList } from './components/NotesList';
import { Settings } from './components/Settings';
import { Theme, getTheme } from './themes';

function App() {
  const [notes, setNotes] = useState<Note[]>([]);
  const [activeNoteId, setActiveNoteId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [showSettings, setShowSettings] = useState(false);
  const [currentThemeName, setCurrentThemeName] = useState('Dark');
  const [theme, setTheme] = useState<Theme>(getTheme('Dark'));

  // Auto-save timer
  const [saveTimeout, setSaveTimeout] = useState<ReturnType<typeof setTimeout> | null>(null);

  // Load notes on mount
  useEffect(() => {
    loadNotes();
    loadTheme();
  }, []);

  const loadNotes = async () => {
    const loadedNotes = await NotesManager.loadNotes();
    setNotes(loadedNotes);

    // Select the first note if available
    if (loadedNotes.length > 0 && !activeNoteId) {
      const sorted = NotesManager.sortNotes(loadedNotes.map(enrichNote));
      if (sorted.length > 0) {
        setActiveNoteId(sorted[0].id);
      }
    }
  };

  const loadTheme = async () => {
    try {
      const settings = await invoke<{ theme: string }>('load_settings');
      if (settings.theme) {
        setCurrentThemeName(settings.theme);
        setTheme(getTheme(settings.theme));
      }
    } catch (error) {
      console.error('Failed to load theme:', error);
    }
  };

  // Save notes to backend (debounced)
  const saveNotes = useCallback(
    (updatedNotes: Note[]) => {
      if (saveTimeout) {
        clearTimeout(saveTimeout);
      }

      const timeout = setTimeout(() => {
        NotesManager.saveNotes(updatedNotes);
      }, 500); // 500ms debounce

      setSaveTimeout(timeout);
    },
    [saveTimeout]
  );

  // Get the active note
  const activeNote = notes.find((n) => n.id === activeNoteId) || null;

  // Get filtered and sorted notes for display
  const getDisplayNotes = (): NoteWithComputed[] => {
    const filtered = NotesManager.searchNotes(notes, searchQuery);
    return NotesManager.sortNotes(filtered);
  };

  // Handlers
  const handleNoteChange = (content: string) => {
    if (!activeNote) return;

    const updatedNote = NotesManager.updateNote(activeNote, { content });
    const updatedNotes = notes.map((n) => (n.id === activeNote.id ? updatedNote : n));

    setNotes(updatedNotes);
    saveNotes(updatedNotes);
  };

  const handleNewNote = () => {
    const newNote = NotesManager.createNote();
    const updatedNotes = [newNote, ...notes];

    setNotes(updatedNotes);
    setActiveNoteId(newNote.id);
    setSearchQuery(''); // Clear search when creating new note
    saveNotes(updatedNotes);
  };

  const handleNoteSelect = (noteId: string) => {
    setActiveNoteId(noteId);
  };

  const handleDeleteNote = (noteId: string) => {
    const updatedNotes = NotesManager.deleteNote(notes, noteId);
    setNotes(updatedNotes);

    // Select another note if the deleted one was active
    if (activeNoteId === noteId) {
      const sorted = NotesManager.sortNotes(updatedNotes.map(enrichNote));
      setActiveNoteId(sorted.length > 0 ? sorted[0].id : null);
    }

    saveNotes(updatedNotes);
  };

  const handlePinNote = (noteId: string) => {
    const note = notes.find((n) => n.id === noteId);
    if (!note) return;

    const updatedNote = { ...note, isPinned: !note.isPinned };
    const updatedNotes = notes.map((n) => (n.id === noteId ? updatedNote : n));

    setNotes(updatedNotes);
    saveNotes(updatedNotes);
  };

  const handleThemeChange = (themeName: string) => {
    setCurrentThemeName(themeName);
    setTheme(getTheme(themeName));
  };

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      // Settings shortcut: Ctrl/Cmd + ,
      if ((e.ctrlKey || e.metaKey) && e.key === ',') {
        e.preventDefault();
        setShowSettings(true);
      }

      // New note shortcut: Ctrl/Cmd + N
      if ((e.ctrlKey || e.metaKey) && e.key === 'n') {
        e.preventDefault();
        handleNewNote();
      }

      // Search shortcut: Ctrl/Cmd + F
      if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
        e.preventDefault();
        const searchInput = document.querySelector('.search-input') as HTMLInputElement;
        if (searchInput) {
          searchInput.focus();
        }
      }
    },
    [notes, activeNoteId]
  );

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  // Apply theme to document
  useEffect(() => {
    document.body.style.backgroundColor = theme.background;
  }, [theme]);

  return (
    <div className="app" style={{ backgroundColor: theme.background }}>
      <div className="toolbar" style={{ backgroundColor: theme.sidebarBackground, borderBottomColor: theme.border }}>
        <div className="toolbar-title" style={{ color: theme.text }}>
          WispMark
        </div>
        <div className="toolbar-actions">
          <button
            className="toolbar-button"
            onClick={() => setShowSettings(true)}
            style={{ color: theme.icon }}
            title="Settings (Ctrl+,)"
          >
            ⚙
          </button>
        </div>
      </div>

      <div className="main-content">
        <NotesList
          notes={getDisplayNotes()}
          activeNoteId={activeNoteId}
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          onNoteSelect={handleNoteSelect}
          onNewNote={handleNewNote}
          onDeleteNote={handleDeleteNote}
          onPinNote={handlePinNote}
          theme={theme}
        />

        <Editor note={activeNote} onChange={handleNoteChange} theme={theme} />
      </div>

      {showSettings && (
        <Settings
          currentTheme={currentThemeName}
          onThemeChange={handleThemeChange}
          onClose={() => setShowSettings(false)}
          theme={theme}
        />
      )}
    </div>
  );
}

export default App;
