import React, { useEffect, useRef, useState } from 'react';
import { Note } from '../models/Note';
import { Theme } from '../themes';

interface EditorProps {
  note: Note | null;
  onChange: (content: string) => void;
  theme: Theme;
}

export const Editor: React.FC<EditorProps> = ({ note, onChange, theme }) => {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [charCount, setCharCount] = useState(0);
  const [wordCount, setWordCount] = useState(0);

  useEffect(() => {
    if (note) {
      setCharCount(note.content.length);
      const words = note.content.trim().split(/\s+/).filter(w => w.length > 0);
      setWordCount(words.length);
    } else {
      setCharCount(0);
      setWordCount(0);
    }
  }, [note]);

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newContent = e.target.value;
    onChange(newContent);
    setCharCount(newContent.length);
    const words = newContent.trim().split(/\s+/).filter(w => w.length > 0);
    setWordCount(words.length);
  };

  if (!note) {
    return (
      <div className="editor-container">
        <div className="editor-empty" style={{ color: theme.secondaryText }}>
          Select a note or create a new one
        </div>
      </div>
    );
  }

  return (
    <div className="editor-container">
      <textarea
        ref={textareaRef}
        className="editor-textarea"
        value={note.content}
        onChange={handleChange}
        placeholder="Start typing..."
        spellCheck={false}
        autoFocus
        style={{
          color: theme.text,
          caretColor: theme.cursor,
          backgroundColor: 'transparent',
        }}
      />
      <div
        className="editor-stats"
        style={{
          color: theme.secondaryText,
          borderTopColor: theme.border,
        }}
      >
        <span>{charCount} characters</span>
        <span className="separator">•</span>
        <span>{wordCount} words</span>
      </div>
    </div>
  );
};
