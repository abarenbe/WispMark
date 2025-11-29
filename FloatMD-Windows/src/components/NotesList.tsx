import React from 'react';
import { NoteWithComputed } from '../models/Note';
import { Theme } from '../themes';

interface NotesListProps {
  notes: NoteWithComputed[];
  activeNoteId: string | null;
  searchQuery: string;
  onSearchChange: (query: string) => void;
  onNoteSelect: (noteId: string) => void;
  onNewNote: () => void;
  onDeleteNote: (noteId: string) => void;
  onPinNote: (noteId: string) => void;
  theme: Theme;
}

export const NotesList: React.FC<NotesListProps> = ({
  notes,
  activeNoteId,
  searchQuery,
  onSearchChange,
  onNoteSelect,
  onNewNote,
  onDeleteNote,
  onPinNote,
  theme,
}) => {
  const formatDate = (isoDate: string): string => {
    const date = new Date(isoDate);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;

    return date.toLocaleDateString();
  };

  return (
    <div
      className="notes-list"
      style={{
        backgroundColor: theme.sidebarBackground,
        borderRightColor: theme.border,
      }}
    >
      <div className="notes-list-header">
        <input
          type="text"
          className="search-input"
          placeholder="Search notes..."
          value={searchQuery}
          onChange={(e) => onSearchChange(e.target.value)}
          style={{
            backgroundColor: theme.background,
            color: theme.text,
            borderColor: theme.border,
          }}
        />
        <button
          className="new-note-button"
          onClick={onNewNote}
          style={{
            backgroundColor: theme.background,
            color: theme.text,
            borderColor: theme.border,
          }}
          title="New Note"
        >
          +
        </button>
      </div>

      <div className="notes-list-content">
        {notes.length === 0 ? (
          <div
            className="notes-list-empty"
            style={{ color: theme.secondaryText }}
          >
            {searchQuery ? 'No notes found' : 'No notes yet'}
          </div>
        ) : (
          notes.map((note) => (
            <div
              key={note.id}
              className={`note-item ${note.id === activeNoteId ? 'active' : ''}`}
              onClick={() => onNoteSelect(note.id)}
              style={{
                backgroundColor:
                  note.id === activeNoteId
                    ? theme.sidebarActive
                    : 'transparent',
                borderLeftColor: note.isPinned ? theme.link : 'transparent',
              }}
              onMouseEnter={(e) => {
                if (note.id !== activeNoteId) {
                  e.currentTarget.style.backgroundColor = theme.sidebarHover;
                }
              }}
              onMouseLeave={(e) => {
                if (note.id !== activeNoteId) {
                  e.currentTarget.style.backgroundColor = 'transparent';
                }
              }}
            >
              <div className="note-item-header">
                <div
                  className="note-item-title"
                  style={{ color: theme.text }}
                >
                  {note.isPinned && (
                    <span className="pin-indicator" style={{ color: theme.link }}>
                      📌{' '}
                    </span>
                  )}
                  {note.title}
                </div>
                <div className="note-item-actions">
                  <button
                    className="note-action-button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onPinNote(note.id);
                    }}
                    style={{ color: theme.icon }}
                    title={note.isPinned ? 'Unpin' : 'Pin'}
                  >
                    {note.isPinned ? '📌' : '📍'}
                  </button>
                  <button
                    className="note-action-button"
                    onClick={(e) => {
                      e.stopPropagation();
                      if (confirm('Delete this note?')) {
                        onDeleteNote(note.id);
                      }
                    }}
                    style={{ color: theme.icon }}
                    title="Delete"
                  >
                    🗑
                  </button>
                </div>
              </div>
              <div
                className="note-item-preview"
                style={{ color: theme.secondaryText }}
              >
                {note.preview}
              </div>
              <div
                className="note-item-footer"
                style={{ color: theme.secondaryText }}
              >
                <span>{formatDate(note.modifiedAt)}</span>
                {note.tags.length > 0 && (
                  <>
                    <span className="separator">•</span>
                    <span className="note-tags">
                      {note.tags.slice(0, 2).map((tag) => (
                        <span
                          key={tag}
                          className="tag-pill"
                          style={{
                            color: theme.tag,
                            backgroundColor: theme.tagBackground,
                          }}
                        >
                          #{tag}
                        </span>
                      ))}
                      {note.tags.length > 2 && (
                        <span className="tag-more">+{note.tags.length - 2}</span>
                      )}
                    </span>
                  </>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
