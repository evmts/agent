/**
 * Tool call formatting with icons and duration tracking.
 */

import pc from 'picocolors';

// Tool-specific icons
const TOOL_ICONS: Record<string, string> = {
  grep: '🔍',
  readFile: '📄',
  writeFile: '✏️',
  multiedit: '📝',
  webFetch: '🌐',
  unifiedExec: '💻',
  writeStdin: '⌨️',
  closePtySession: '🚪',
  listPtySessions: '📋',
  default: '🔧',
};

/**
 * Get icon for a tool
 */
export function getToolIcon(toolName: string): string {
  return TOOL_ICONS[toolName] || TOOL_ICONS.default;
}

/**
 * Truncate text with ellipsis
 */
function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return `${text.slice(0, maxLen - 3)}...`;
}

/**
 * Format tool-specific input preview
 */
export function formatToolInput(toolName: string, input?: Record<string, any>): string {
  if (!input || Object.keys(input).length === 0) return '';

  const width = process.stdout.columns || 80;
  const maxPreviewWidth = Math.min(width - 10, 70);

  switch (toolName) {
    case 'grep':
      return pc.dim(`pattern: "${input.pattern}" in ${input.path || '.'}`);

    case 'readFile':
      return pc.dim(`${input.path}${input.lines ? `:${input.lines}` : ''}`);

    case 'writeFile':
      const contentPreview = truncate((input.content || '').replace(/\n/g, '\\n'), 40);
      return pc.dim(`${input.path} (${contentPreview})`);

    case 'multiedit':
      const editCount = input.edits?.length || 0;
      return pc.dim(`${editCount} edit${editCount !== 1 ? 's' : ''} in ${input.path}`);

    case 'unifiedExec':
      return pc.dim(`$ ${truncate(input.command || '', maxPreviewWidth)}`);

    case 'webFetch':
      return pc.dim(truncate(input.url || '', maxPreviewWidth));

    default:
      return pc.dim(truncate(JSON.stringify(input), maxPreviewWidth));
  }
}

/**
 * Format a tool call for display
 */
export function formatToolCall(toolName: string, input?: Record<string, any>): string {
  const icon = getToolIcon(toolName);
  const inputPreview = formatToolInput(toolName, input);

  let output = `  ${icon} ${pc.cyan(toolName)}`;
  if (inputPreview) {
    output += `\n     ${inputPreview}`;
  }
  return output;
}

/**
 * Format a tool result for display
 */
export function formatToolResult(
  toolName: string,
  output?: string,
  duration?: number
): string {
  const icon = getToolIcon(toolName);
  const durationStr = duration !== undefined ? pc.dim(` (${duration}ms)`) : '';

  if (!output) {
    return `  ${icon} ${pc.dim('←')} ${pc.dim('done')}${durationStr}`;
  }

  const preview = truncate(output.replace(/\n/g, ' '), 70);
  return `  ${icon} ${pc.dim('←')} ${pc.dim(preview)}${durationStr}`;
}

/**
 * Tool call state tracker for duration measurement
 */
export class ToolCallTracker {
  private startTimes: Map<string, number> = new Map();

  /**
   * Record when a tool call starts
   */
  start(toolName: string): void {
    this.startTimes.set(toolName, Date.now());
  }

  /**
   * Get duration since tool call started
   */
  getDuration(toolName: string): number | undefined {
    const startTime = this.startTimes.get(toolName);
    if (startTime === undefined) return undefined;
    return Date.now() - startTime;
  }

  /**
   * Clear tracking for a tool
   */
  clear(toolName: string): void {
    this.startTimes.delete(toolName);
  }

  /**
   * Reset all tracking
   */
  reset(): void {
    this.startTimes.clear();
  }
}
