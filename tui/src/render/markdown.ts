/**
 * Simple streaming-aware markdown renderer for terminal output.
 *
 * Renders basic markdown formatting with ANSI codes:
 * - **bold** and __bold__
 * - *italic* and _italic_
 * - `inline code`
 * - # Headers
 * - - Bullet lists
 * - Code blocks (```lang ... ```)
 */

import pc from 'picocolors';

type RenderState =
  | { mode: 'text' }
  | { mode: 'codeblock'; lang: string; buffer: string };

/**
 * Streaming markdown renderer
 */
export class MarkdownRenderer {
  private state: RenderState = { mode: 'text' };
  private buffer = '';

  /**
   * Push a text delta and get any immediately renderable content
   */
  push(delta: string): string {
    this.buffer += delta;
    return this.processBuffer();
  }

  /**
   * Flush any remaining buffered content
   */
  flush(): string {
    const result = this.renderText(this.buffer);
    this.buffer = '';
    this.state = { mode: 'text' };
    return result;
  }

  /**
   * Reset state for a new message
   */
  reset(): void {
    this.buffer = '';
    this.state = { mode: 'text' };
  }

  /**
   * Process the buffer and return renderable content
   */
  private processBuffer(): string {
    // Check for code block transitions
    if (this.state.mode === 'text') {
      const codeBlockStart = this.buffer.match(/```(\w*)\n?/);
      if (codeBlockStart) {
        const beforeBlock = this.buffer.slice(0, codeBlockStart.index);
        const afterStart = this.buffer.slice(
          (codeBlockStart.index || 0) + codeBlockStart[0].length
        );

        // Render text before code block
        const rendered = this.renderText(beforeBlock);

        // Enter code block mode
        this.state = { mode: 'codeblock', lang: codeBlockStart[1] || '', buffer: '' };
        this.buffer = afterStart;

        // Check if code block ends in same delta
        return rendered + this.processBuffer();
      }

      // If we have complete lines, render them
      const lastNewline = this.buffer.lastIndexOf('\n');
      if (lastNewline >= 0) {
        const complete = this.buffer.slice(0, lastNewline + 1);
        this.buffer = this.buffer.slice(lastNewline + 1);
        return this.renderText(complete);
      }

      return '';
    }

    // In code block mode, look for closing ```
    if (this.state.mode === 'codeblock') {
      const closeMatch = this.buffer.match(/\n?```/);
      if (closeMatch) {
        const codeContent = this.buffer.slice(0, closeMatch.index);
        const afterBlock = this.buffer.slice(
          (closeMatch.index || 0) + closeMatch[0].length
        );

        // Render code block
        const rendered = this.renderCodeBlock(
          this.state.lang,
          this.state.buffer + codeContent
        );

        // Exit code block mode
        this.state = { mode: 'text' };
        this.buffer = afterBlock;

        return rendered + this.processBuffer();
      }

      // Buffer more code content
      this.state.buffer += this.buffer;
      this.buffer = '';
      return '';
    }

    return '';
  }

  /**
   * Render inline markdown formatting
   */
  private renderText(text: string): string {
    if (!text) return '';

    let result = text;

    // Headers (only at line start)
    result = result.replace(/^### (.+)$/gm, pc.bold('$1'));
    result = result.replace(/^## (.+)$/gm, pc.bold(pc.blue('$1')));
    result = result.replace(/^# (.+)$/gm, pc.bold(pc.cyan('$1')));

    // Bold (** or __)
    result = result.replace(/\*\*(.+?)\*\*/g, pc.bold('$1'));
    result = result.replace(/__(.+?)__/g, pc.bold('$1'));

    // Italic (* or _) - but not inside words
    result = result.replace(/(?<![a-zA-Z])\*([^*]+)\*(?![a-zA-Z])/g, pc.italic('$1'));
    result = result.replace(/(?<![a-zA-Z])_([^_]+)_(?![a-zA-Z])/g, pc.italic('$1'));

    // Inline code
    result = result.replace(/`([^`]+)`/g, pc.cyan('$1'));

    // Bullet lists
    result = result.replace(/^(\s*)[*-] /gm, '$1• ');

    // Links [text](url)
    result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, `$1 ${pc.dim('($2)')}`);

    return result;
  }

  /**
   * Render a code block with optional syntax highlighting
   */
  private renderCodeBlock(lang: string, code: string): string {
    const trimmedCode = code.trim();
    if (!trimmedCode) return '';

    const lines = trimmedCode.split('\n');
    const langLabel = lang ? pc.dim(`[${lang}]`) : '';
    const border = pc.dim('│');

    let result = '\n';
    if (langLabel) {
      result += `  ${langLabel}\n`;
    }

    for (const line of lines) {
      // Basic syntax highlighting based on common patterns
      let highlighted = line;

      if (lang === 'typescript' || lang === 'ts' || lang === 'javascript' || lang === 'js') {
        highlighted = highlightJS(line);
      } else if (lang === 'bash' || lang === 'sh' || lang === 'shell') {
        highlighted = highlightBash(line);
      } else if (lang === 'json') {
        highlighted = highlightJSON(line);
      }

      result += `  ${border} ${highlighted}\n`;
    }

    return result;
  }
}

/**
 * Basic JavaScript/TypeScript syntax highlighting
 */
function highlightJS(line: string): string {
  let result = line;

  // Keywords
  const keywords =
    /\b(const|let|var|function|return|if|else|for|while|class|interface|type|import|export|from|async|await|new|this|extends|implements)\b/g;
  result = result.replace(keywords, pc.magenta('$1'));

  // Strings
  result = result.replace(/(['"`])(?:(?!\1)[^\\]|\\.)*\1/g, (match) => pc.green(match));

  // Comments
  result = result.replace(/(\/\/.*$)/gm, pc.dim('$1'));

  // Numbers
  result = result.replace(/\b(\d+(?:\.\d+)?)\b/g, pc.yellow('$1'));

  return result;
}

/**
 * Basic bash syntax highlighting
 */
function highlightBash(line: string): string {
  let result = line;

  // Comments
  if (result.trim().startsWith('#')) {
    return pc.dim(result);
  }

  // Commands at start
  result = result.replace(/^(\s*)(\w+)/, (_, space, cmd) => space + pc.cyan(cmd));

  // Flags
  result = result.replace(/(\s)(--?[\w-]+)/g, (_, space, flag) => space + pc.yellow(flag));

  // Strings
  result = result.replace(/(['"])(?:(?!\1)[^\\]|\\.)*\1/g, (match) => pc.green(match));

  return result;
}

/**
 * Basic JSON syntax highlighting
 */
function highlightJSON(line: string): string {
  let result = line;

  // Keys
  result = result.replace(/"([^"]+)":/g, pc.cyan('"$1"') + ':');

  // String values
  result = result.replace(/:\s*"([^"]*)"/g, ': ' + pc.green('"$1"'));

  // Numbers and booleans
  result = result.replace(/:\s*(true|false|null|\d+(?:\.\d+)?)/g, (_, val) =>
    ': ' + pc.yellow(val)
  );

  return result;
}

/**
 * Simple function to render markdown without streaming
 */
export function renderMarkdown(text: string): string {
  const renderer = new MarkdownRenderer();
  renderer.push(text);
  return renderer.flush();
}
