export interface Note {
  id: string;
  content: string;
  createdAt: Date;
  modifiedAt: Date;
  isPinned: boolean;
}

export type TokenType =
  | 'heading'
  | 'bold'
  | 'italic'
  | 'code'
  | 'codeBlock'
  | 'link'
  | 'wikiLink'
  | 'tag'
  | 'checkbox'
  | 'blockquote'
  | 'listItem'
  | 'text';

export interface MarkdownToken {
  type: TokenType;
  content: string;
  level?: number; // For headings (1-6)
  checked?: boolean; // For checkboxes
  url?: string; // For links
}

export interface AutocompletePosition {
  x: number;
  y: number;
}

export type TriggerType = 'wikilink' | 'tag';
