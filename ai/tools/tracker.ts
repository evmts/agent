/**
 * Tool call tracker for detecting and preventing duplicate operations.
 *
 * Tracks recent tool calls per session to avoid redundant operations like
 * reading the same file multiple times or running identical grep queries.
 */

export interface ToolCall {
  toolName: string;
  args: Record<string, unknown>;
  result: string;
  timestamp: number;
}

export interface DuplicateCheck {
  isDuplicate: boolean;
  previousResult?: string;
  previousTimestamp?: number;
}

/**
 * Per-tool similarity checker functions.
 * Each tool can define its own logic for determining if two calls are duplicates.
 */
type SimilarityChecker = (
  currentArgs: Record<string, unknown>,
  previousArgs: Record<string, unknown>
) => boolean;

const similarityCheckers: Record<string, SimilarityChecker> = {
  // readFile: duplicate if same file path (offset/limit don't matter much)
  readFile: (current, previous) => {
    return current.filePath === previous.filePath;
  },

  // grep: duplicate if same pattern and path
  grep: (current, previous) => {
    return (
      current.pattern === previous.pattern &&
      current.path === previous.path &&
      current.glob === previous.glob &&
      current.multiline === previous.multiline &&
      current.caseInsensitive === previous.caseInsensitive
    );
  },

  // writeFile: duplicate if same path AND same content
  writeFile: (current, previous) => {
    return (
      current.filePath === previous.filePath &&
      current.content === previous.content
    );
  },

  // multiedit: duplicate if same edits (unlikely but possible)
  multiedit: (current, previous) => {
    return JSON.stringify(current.edits) === JSON.stringify(previous.edits);
  },

  // webFetch: duplicate if same URL
  webFetch: (current, previous) => {
    return current.url === previous.url;
  },

  // listPtySessions: always allow (stateful operation)
  listPtySessions: () => false,

  // closePtySession: always allow (stateful operation)
  closePtySession: () => false,

  // Never consider these as duplicates (they execute code/have side effects)
  unifiedExec: () => false,
  writeStdin: () => false,
};

/**
 * Generic fallback similarity checker for tools without custom logic.
 * Matches if more than half of the arguments are identical.
 */
function genericSimilarityCheck(
  currentArgs: Record<string, unknown>,
  previousArgs: Record<string, unknown>
): boolean {
  if (!currentArgs || !previousArgs) return false;

  const keys = Object.keys(currentArgs);
  if (keys.length === 0) return false;

  let matches = 0;
  let exactMatch = false;

  for (const key of keys) {
    if (previousArgs[key] !== undefined) {
      if (typeof currentArgs[key] === 'string' && typeof previousArgs[key] === 'string') {
        // Case-insensitive string comparison
        if ((currentArgs[key] as string).toLowerCase() === (previousArgs[key] as string).toLowerCase()) {
          matches++;
          // ID/path/name fields are critical identifiers
          if (key.includes('id') || key.includes('Id') || key === 'name' || key.includes('path') || key.includes('Path')) {
            exactMatch = true;
          }
        }
      } else if (currentArgs[key] === previousArgs[key]) {
        // Exact comparison for non-string values
        matches++;
      }
    }
  }

  // Consider similar if:
  // 1. More than half properties match, or
  // 2. There's at least one match AND it's an ID/path/name field (critical identifier)
  return (matches > 0 && matches >= keys.length / 2) || (matches > 0 && exactMatch);
}

/**
 * Tool call tracker class.
 *
 * Maintains a per-session history of tool calls with configurable limits.
 */
export class ToolCallTracker {
  private history: Map<string, ToolCall[]> = new Map();
  private readonly maxHistoryPerSession: number;
  private readonly maxAgeMs: number;

  constructor(
    maxHistoryPerSession: number = 50,
    maxAgeMs: number = 5 * 60 * 1000 // 5 minutes default
  ) {
    this.maxHistoryPerSession = maxHistoryPerSession;
    this.maxAgeMs = maxAgeMs;
  }

  /**
   * Check if a tool call is a duplicate of a recent call.
   *
   * @param sessionId - Session identifier
   * @param toolName - Name of the tool being called
   * @param args - Tool arguments
   * @returns DuplicateCheck result with cached result if duplicate
   */
  checkDuplicate(
    sessionId: string,
    toolName: string,
    args: Record<string, unknown>
  ): DuplicateCheck {
    const sessionHistory = this.history.get(sessionId);
    if (!sessionHistory || sessionHistory.length === 0) {
      return { isDuplicate: false };
    }

    const now = Date.now();
    const checker = similarityCheckers[toolName] ?? genericSimilarityCheck;

    // Check recent calls of the same tool (limit to last 3 for efficiency)
    const recentCalls = sessionHistory
      .filter((call) => call.toolName === toolName)
      .slice(-3);

    for (const call of recentCalls) {
      // Skip if too old
      if (now - call.timestamp > this.maxAgeMs) {
        continue;
      }

      // Check if similar using tool-specific or generic logic
      if (checker(args, call.args)) {
        return {
          isDuplicate: true,
          previousResult: call.result,
          previousTimestamp: call.timestamp,
        };
      }
    }

    return { isDuplicate: false };
  }

  /**
   * Record a tool call in the session history.
   *
   * @param sessionId - Session identifier
   * @param toolName - Name of the tool
   * @param args - Tool arguments
   * @param result - Tool result
   */
  recordCall(
    sessionId: string,
    toolName: string,
    args: Record<string, unknown>,
    result: string
  ): void {
    let sessionHistory = this.history.get(sessionId);

    if (!sessionHistory) {
      sessionHistory = [];
      this.history.set(sessionId, sessionHistory);
    }

    // Add new call
    sessionHistory.push({
      toolName,
      args,
      result,
      timestamp: Date.now(),
    });

    // Trim to max history size
    if (sessionHistory.length > this.maxHistoryPerSession) {
      sessionHistory.splice(0, sessionHistory.length - this.maxHistoryPerSession);
    }

    // Clean up old entries
    this.cleanupOldEntries();
  }

  /**
   * Clear history for a specific session.
   *
   * @param sessionId - Session identifier
   */
  clearSession(sessionId: string): void {
    this.history.delete(sessionId);
  }

  /**
   * Clear all history.
   */
  clearAll(): void {
    this.history.clear();
  }

  /**
   * Remove entries older than maxAgeMs across all sessions.
   */
  private cleanupOldEntries(): void {
    const now = Date.now();

    for (const [sessionId, calls] of this.history.entries()) {
      const filtered = calls.filter((call) => now - call.timestamp <= this.maxAgeMs);

      if (filtered.length === 0) {
        this.history.delete(sessionId);
      } else if (filtered.length < calls.length) {
        this.history.set(sessionId, filtered);
      }
    }
  }

  /**
   * Get statistics about the tracker state (for debugging/monitoring).
   */
  getStats(): {
    totalSessions: number;
    totalCalls: number;
    callsByTool: Record<string, number>;
  } {
    const callsByTool: Record<string, number> = {};
    let totalCalls = 0;

    for (const calls of this.history.values()) {
      totalCalls += calls.length;
      for (const call of calls) {
        callsByTool[call.toolName] = (callsByTool[call.toolName] ?? 0) + 1;
      }
    }

    return {
      totalSessions: this.history.size,
      totalCalls,
      callsByTool,
    };
  }
}

// Global singleton tracker instance
let globalTracker: ToolCallTracker | null = null;

/**
 * Get the global tool call tracker instance.
 * Creates one if it doesn't exist.
 */
export function getToolCallTracker(): ToolCallTracker {
  if (!globalTracker) {
    globalTracker = new ToolCallTracker();
  }
  return globalTracker;
}

/**
 * Set a custom tool call tracker instance (useful for testing).
 */
export function setToolCallTracker(tracker: ToolCallTracker | null): void {
  globalTracker = tracker;
}
