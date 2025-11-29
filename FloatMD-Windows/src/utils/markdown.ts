import { MarkdownToken } from '../types';

/**
 * Extract the title from markdown content (first non-empty line)
 */
export function extractTitle(content: string): string {
  const lines = content.split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;

    // Skip heading markers
    if (trimmed.startsWith('#')) {
      const withoutHashes = trimmed.replace(/^#+\s*/, '');
      if (withoutHashes.length > 0) {
        return withoutHashes.substring(0, 50);
      }
      continue;
    }

    return trimmed.substring(0, 50);
  }

  return 'Untitled';
}

/**
 * Extract all tags from markdown content (#tagname pattern)
 */
export function extractTags(content: string): string[] {
  const pattern = /#([a-zA-Z][a-zA-Z0-9_-]*)/g;
  const tags = new Set<string>();

  let match;
  while ((match = pattern.exec(content)) !== null) {
    tags.add(match[1].toLowerCase());
  }

  return Array.from(tags).sort();
}

/**
 * Extract all wiki links from markdown content ([[Title]] pattern)
 */
export function extractWikiLinks(content: string): string[] {
  const pattern = /\[\[([^\]]+)\]\]/g;
  const links = new Set<string>();

  let match;
  while ((match = pattern.exec(content)) !== null) {
    links.add(match[1].trim());
  }

  return Array.from(links);
}

/**
 * Get a preview of the markdown content (cleaned of markdown syntax)
 */
export function getPreview(content: string, maxLength: number = 100): string {
  const lines = content.split(/\r?\n/);
  const previewLines: string[] = [];
  let foundTitle = false;

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;

    // Skip the first non-empty line (title)
    if (!foundTitle) {
      foundTitle = true;
      continue;
    }

    // Clean markdown syntax for preview
    let clean = trimmed;
    clean = clean.replace(/^#+\s*/, ''); // Remove headings
    clean = clean.replace(/\*\*(.+?)\*\*/g, '$1'); // Remove bold
    clean = clean.replace(/\*(.+?)\*/g, '$1'); // Remove italic
    clean = clean.replace(/`(.+?)`/g, '$1'); // Remove inline code
    clean = clean.replace(/\[\[(.+?)\]\]/g, '$1'); // Remove wiki links
    clean = clean.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1'); // Remove links

    previewLines.push(clean);
    if (previewLines.length >= 2) break;
  }

  const preview = previewLines.join(' ');
  return preview.substring(0, maxLength);
}

/**
 * Parse markdown content into tokens for syntax highlighting
 */
export function parseMarkdown(content: string): MarkdownToken[] {
  const tokens: MarkdownToken[] = [];
  const lines = content.split(/\r?\n/);
  let inCodeBlock = false;
  let codeBlockContent = '';

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Handle code blocks
    if (line.trim().startsWith('```')) {
      if (inCodeBlock) {
        // End of code block
        tokens.push({
          type: 'codeBlock',
          content: codeBlockContent,
        });
        codeBlockContent = '';
        inCodeBlock = false;
      } else {
        // Start of code block
        inCodeBlock = true;
        codeBlockContent = line + '\n';
      }
      continue;
    }

    if (inCodeBlock) {
      codeBlockContent += line + '\n';
      continue;
    }

    // Parse line-level elements
    const lineTokens = parseLine(line);
    tokens.push(...lineTokens);

    // Add newline token if not last line
    if (i < lines.length - 1) {
      tokens.push({ type: 'text', content: '\n' });
    }
  }

  // Handle unclosed code block
  if (inCodeBlock && codeBlockContent) {
    tokens.push({
      type: 'codeBlock',
      content: codeBlockContent,
    });
  }

  return tokens;
}

/**
 * Parse a single line into tokens
 */
function parseLine(line: string): MarkdownToken[] {
  const tokens: MarkdownToken[] = [];

  // Check for heading
  const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);
  if (headingMatch) {
    return [{
      type: 'heading',
      content: line,
      level: headingMatch[1].length,
    }];
  }

  // Check for blockquote
  if (line.trimStart().startsWith('>')) {
    return [{
      type: 'blockquote',
      content: line,
    }];
  }

  // Check for checkbox
  const checkboxMatch = line.match(/^(\s*[-*])\s+\[([ x])\]\s+(.+)$/);
  if (checkboxMatch) {
    return [{
      type: 'checkbox',
      content: line,
      checked: checkboxMatch[2].toLowerCase() === 'x',
    }];
  }

  // Check for list item
  const listMatch = line.match(/^(\s*[-*+]|\s*\d+\.)\s+(.+)$/);
  if (listMatch) {
    // Parse inline elements in list content
    const inlineTokens = parseInlineElements(listMatch[2]);
    return [{
      type: 'listItem',
      content: listMatch[1] + ' ',
    }, ...inlineTokens];
  }

  // Parse inline elements
  return parseInlineElements(line);
}

/**
 * Parse inline markdown elements (bold, italic, code, links, wiki links, tags)
 */
function parseInlineElements(text: string): MarkdownToken[] {
  const result: MarkdownToken[] = [];
  let position = 0;

  // Pattern to match all inline elements
  const pattern = /(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|\[([^\]]+)\]\(([^)]+)\)|\[\[([^\]]+)\]\]|#([a-zA-Z][a-zA-Z0-9_-]*))/g;

  let match;
  while ((match = pattern.exec(text)) !== null) {
    // Add text before the match
    if (match.index > position) {
      const textBefore = text.substring(position, match.index);
      if (textBefore) {
        result.push({ type: 'text', content: textBefore });
      }
    }

    // Add the matched token
    if (match[2]) {
      // Bold **text**
      result.push({ type: 'bold', content: match[0] });
    } else if (match[3]) {
      // Italic *text*
      result.push({ type: 'italic', content: match[0] });
    } else if (match[4]) {
      // Inline code `text`
      result.push({ type: 'code', content: match[0] });
    } else if (match[5] && match[6]) {
      // Link [text](url)
      result.push({ type: 'link', content: match[0], url: match[6] });
    } else if (match[7]) {
      // Wiki link [[Title]]
      result.push({ type: 'wikiLink', content: match[0] });
    } else if (match[8]) {
      // Tag #tagname
      result.push({ type: 'tag', content: match[0] });
    }

    position = match.index + match[0].length;
  }

  // Add remaining text
  if (position < text.length) {
    const textAfter = text.substring(position);
    if (textAfter) {
      result.push({ type: 'text', content: textAfter });
    }
  }

  // If no matches, return the whole text as a single token
  if (result.length === 0) {
    return [{ type: 'text', content: text }];
  }

  return result;
}
