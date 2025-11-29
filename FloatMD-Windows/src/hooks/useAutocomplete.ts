import { useState, useEffect, useCallback, useRef } from 'react';
import { AutocompletePosition, TriggerType, Note } from '../types';
import { extractTitle, extractTags } from '../utils/markdown';

export interface AutocompleteState {
  showAutocomplete: boolean;
  suggestions: string[];
  position: AutocompletePosition;
  triggerType: TriggerType | null;
  query: string;
}

export interface UseAutocompleteOptions {
  notes: Note[];
  editorRef: React.RefObject<HTMLTextAreaElement>;
}

export interface UseAutocompleteResult {
  showAutocomplete: boolean;
  suggestions: string[];
  position: AutocompletePosition;
  triggerType: TriggerType | null;
  query: string;
  handleSelect: (suggestion: string) => void;
  hideAutocomplete: () => void;
}

export function useAutocomplete({
  notes,
  editorRef,
}: UseAutocompleteOptions): UseAutocompleteResult {
  const [state, setState] = useState<AutocompleteState>({
    showAutocomplete: false,
    suggestions: [],
    position: { x: 0, y: 0 },
    triggerType: null,
    query: '',
  });

  const triggerStartRef = useRef<number | null>(null);

  // Get all unique tags from all notes
  const getAllTags = useCallback((): string[] => {
    const tagSet = new Set<string>();
    notes.forEach(note => {
      const tags = extractTags(note.content);
      tags.forEach(tag => tagSet.add(tag));
    });
    return Array.from(tagSet).sort();
  }, [notes]);

  // Get all note titles
  const getAllTitles = useCallback((): string[] => {
    return notes
      .map(note => extractTitle(note.content))
      .filter(title => title !== 'Untitled')
      .sort();
  }, [notes]);

  // Calculate cursor position for autocomplete popup
  const getCursorPosition = useCallback((): AutocompletePosition => {
    const editor = editorRef.current;
    if (!editor) return { x: 0, y: 0 };

    const cursorPosition = editor.selectionStart;
    const textBeforeCursor = editor.value.substring(0, cursorPosition);
    const lines = textBeforeCursor.split('\n');
    const currentLine = lines.length;

    // Approximate position based on line height and character width
    const lineHeight = 20; // Adjust based on your editor's line height
    const charWidth = 8; // Approximate character width
    const currentLineText = lines[lines.length - 1];

    const editorRect = editor.getBoundingClientRect();
    const x = editorRect.left + (currentLineText.length * charWidth);
    const y = editorRect.top + (currentLine * lineHeight);

    return { x, y };
  }, [editorRef]);

  // Detect autocomplete trigger
  const detectTrigger = useCallback((text: string, cursorPos: number) => {
    const textBeforeCursor = text.substring(0, cursorPos);

    // Check for wiki link trigger [[
    const wikiLinkMatch = textBeforeCursor.match(/\[\[([^\]]*)$/);
    if (wikiLinkMatch) {
      const query = wikiLinkMatch[1];
      const triggerStart = cursorPos - query.length;
      triggerStartRef.current = triggerStart;

      setState({
        showAutocomplete: true,
        suggestions: getAllTitles(),
        position: getCursorPosition(),
        triggerType: 'wikilink',
        query,
      });
      return;
    }

    // Check for tag trigger #
    const tagMatch = textBeforeCursor.match(/#([a-zA-Z0-9_-]*)$/);
    if (tagMatch) {
      const query = tagMatch[1];
      const triggerStart = cursorPos - query.length - 1; // -1 for the # symbol
      triggerStartRef.current = triggerStart;

      setState({
        showAutocomplete: true,
        suggestions: getAllTags(),
        position: getCursorPosition(),
        triggerType: 'tag',
        query,
      });
      return;
    }

    // No trigger found, hide autocomplete
    setState(prev => ({
      ...prev,
      showAutocomplete: false,
      triggerType: null,
      query: '',
    }));
    triggerStartRef.current = null;
  }, [getAllTags, getAllTitles, getCursorPosition]);

  // Handle input changes in the editor
  useEffect(() => {
    const editor = editorRef.current;
    if (!editor) return;

    const handleInput = () => {
      const cursorPos = editor.selectionStart;
      const text = editor.value;
      detectTrigger(text, cursorPos);
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      // Let the Autocomplete component handle these keys
      if (state.showAutocomplete && ['ArrowDown', 'ArrowUp', 'Enter', 'Escape'].includes(e.key)) {
        return;
      }

      // Close autocomplete on certain keys
      if (state.showAutocomplete && ['ArrowLeft', 'ArrowRight'].includes(e.key)) {
        setState(prev => ({ ...prev, showAutocomplete: false, triggerType: null }));
        triggerStartRef.current = null;
      }
    };

    const handleClick = () => {
      const cursorPos = editor.selectionStart;
      const text = editor.value;
      detectTrigger(text, cursorPos);
    };

    editor.addEventListener('input', handleInput);
    editor.addEventListener('keydown', handleKeyDown);
    editor.addEventListener('click', handleClick);

    return () => {
      editor.removeEventListener('input', handleInput);
      editor.removeEventListener('keydown', handleKeyDown);
      editor.removeEventListener('click', handleClick);
    };
  }, [editorRef, state.showAutocomplete, detectTrigger]);

  // Handle autocomplete selection
  const handleSelect = useCallback((suggestion: string) => {
    const editor = editorRef.current;
    if (!editor || triggerStartRef.current === null || !state.triggerType) {
      setState(prev => ({ ...prev, showAutocomplete: false, triggerType: null }));
      return;
    }

    // Empty string signals cancellation
    if (suggestion === '') {
      setState(prev => ({ ...prev, showAutocomplete: false, triggerType: null }));
      triggerStartRef.current = null;
      return;
    }

    const cursorPos = editor.selectionStart;
    const text = editor.value;

    // Calculate replacement text
    let replacement: string;
    let startPos = triggerStartRef.current;

    if (state.triggerType === 'wikilink') {
      replacement = `[[${suggestion}]]`;
      // Remove the [[ trigger
      startPos = text.lastIndexOf('[[', cursorPos);
    } else {
      replacement = `#${suggestion}`;
      // Remove the # trigger
      startPos = text.lastIndexOf('#', cursorPos);
    }

    if (startPos === -1) {
      setState(prev => ({ ...prev, showAutocomplete: false, triggerType: null }));
      triggerStartRef.current = null;
      return;
    }

    // Insert the replacement
    const newText = text.substring(0, startPos) + replacement + text.substring(cursorPos);
    editor.value = newText;

    // Set cursor position after the replacement
    const newCursorPos = startPos + replacement.length;
    editor.setSelectionRange(newCursorPos, newCursorPos);

    // Trigger input event to update React state if controlled
    const event = new Event('input', { bubbles: true });
    editor.dispatchEvent(event);

    // Hide autocomplete
    setState(prev => ({ ...prev, showAutocomplete: false, triggerType: null }));
    triggerStartRef.current = null;

    // Focus back to editor
    editor.focus();
  }, [editorRef, state.triggerType]);

  // Hide autocomplete manually
  const hideAutocomplete = useCallback(() => {
    setState(prev => ({ ...prev, showAutocomplete: false, triggerType: null }));
    triggerStartRef.current = null;
  }, []);

  return {
    showAutocomplete: state.showAutocomplete,
    suggestions: state.suggestions,
    position: state.position,
    triggerType: state.triggerType,
    query: state.query,
    handleSelect,
    hideAutocomplete,
  };
}

export default useAutocomplete;
