import { useEffect, useState, useRef } from 'react';
import { AutocompletePosition, TriggerType } from '../types';

export interface AutocompleteProps {
  suggestions: string[];
  onSelect: (suggestion: string) => void;
  position: AutocompletePosition;
  visible: boolean;
  triggerType?: TriggerType;
  query?: string;
}

export const Autocomplete: React.FC<AutocompleteProps> = ({
  suggestions,
  onSelect,
  position,
  visible,
  triggerType = 'wikilink',
  query = '',
}) => {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [filteredSuggestions, setFilteredSuggestions] = useState<string[]>([]);
  const containerRef = useRef<HTMLDivElement>(null);

  // Filter suggestions based on query
  useEffect(() => {
    if (!query) {
      setFilteredSuggestions(suggestions);
      return;
    }

    const lowercaseQuery = query.toLowerCase();
    const filtered = suggestions.filter(suggestion =>
      suggestion.toLowerCase().includes(lowercaseQuery)
    );
    setFilteredSuggestions(filtered);
    setSelectedIndex(0);
  }, [query, suggestions]);

  // Reset selected index when suggestions change
  useEffect(() => {
    setSelectedIndex(0);
  }, [filteredSuggestions]);

  // Handle keyboard navigation
  useEffect(() => {
    if (!visible) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (!filteredSuggestions.length) return;

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setSelectedIndex(prev =>
            prev < filteredSuggestions.length - 1 ? prev + 1 : 0
          );
          break;

        case 'ArrowUp':
          e.preventDefault();
          setSelectedIndex(prev =>
            prev > 0 ? prev - 1 : filteredSuggestions.length - 1
          );
          break;

        case 'Enter':
          e.preventDefault();
          if (filteredSuggestions[selectedIndex]) {
            onSelect(filteredSuggestions[selectedIndex]);
          }
          break;

        case 'Escape':
          e.preventDefault();
          onSelect(''); // Empty string signals cancellation
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [visible, filteredSuggestions, selectedIndex, onSelect]);

  // Auto-scroll selected item into view
  useEffect(() => {
    if (containerRef.current) {
      const selectedElement = containerRef.current.children[selectedIndex] as HTMLElement;
      if (selectedElement) {
        selectedElement.scrollIntoView({
          block: 'nearest',
          behavior: 'smooth',
        });
      }
    }
  }, [selectedIndex]);

  if (!visible || !filteredSuggestions.length) {
    return null;
  }

  const displayedSuggestions = filteredSuggestions.slice(0, 10);

  return (
    <div
      ref={containerRef}
      className="autocomplete-container"
      style={{
        position: 'absolute',
        left: `${position.x}px`,
        top: `${position.y}px`,
        minWidth: '200px',
        maxWidth: '300px',
        maxHeight: '300px',
        overflowY: 'auto',
        backgroundColor: 'var(--background-secondary, #1e1e1e)',
        border: '1px solid var(--border-color, #3e3e3e)',
        borderRadius: '8px',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.3)',
        zIndex: 1000,
      }}
    >
      {displayedSuggestions.map((suggestion, index) => (
        <div
          key={suggestion}
          className={`autocomplete-item ${index === selectedIndex ? 'selected' : ''}`}
          onClick={() => onSelect(suggestion)}
          style={{
            padding: '10px 12px',
            cursor: 'pointer',
            backgroundColor: index === selectedIndex
              ? 'var(--selection-background, #2a2a2a)'
              : 'transparent',
            borderBottom: index < displayedSuggestions.length - 1
              ? '1px solid var(--border-color, #3e3e3e)'
              : 'none',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
          }}
          onMouseEnter={() => setSelectedIndex(index)}
        >
          {triggerType === 'tag' ? (
            <>
              <span style={{ color: 'var(--tag-color, #22c55e)' }}>
                #{suggestion}
              </span>
            </>
          ) : (
            <>
              <span style={{ color: 'var(--link-color, #06b6d4)' }}>📄</span>
              <span style={{ color: 'var(--text-primary, #ffffff)' }}>
                {suggestion}
              </span>
            </>
          )}
        </div>
      ))}
    </div>
  );
};

export default Autocomplete;
