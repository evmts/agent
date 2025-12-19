/**
 * Session model - represents an agent conversation session.
 */

export interface SessionTime {
  created: number;
  updated: number;
  archived?: number;
}

export interface SessionSummary {
  additions: number;
  deletions: number;
  files: number;
}

export interface RevertInfo {
  messageID: string;
  partID?: string;
  snapshot?: string;
}

export interface CompactionInfo {
  originalCount: number;
  compactedAt: number;
}

export interface GhostCommitInfo {
  enabled: boolean;
  currentTurn: number;
  commits: string[];
}

export interface Session {
  id: string;
  projectID: string;
  directory: string;
  title: string;
  version: string;
  time: SessionTime;
  parentID?: string;
  forkPoint?: string;
  summary?: SessionSummary;
  revert?: RevertInfo;
  compaction?: CompactionInfo;
  tokenCount: number;
  bypassMode: boolean;
  model?: string;
  reasoningEffort?: 'minimal' | 'low' | 'medium' | 'high';
  ghostCommit?: GhostCommitInfo;
  plugins: string[];
}

export interface CreateSessionOptions {
  directory: string;
  title?: string;
  parentID?: string;
  bypassMode?: boolean;
  model?: string;
  reasoningEffort?: 'minimal' | 'low' | 'medium' | 'high';
  plugins?: string[];
}

export interface UpdateSessionOptions {
  title?: string;
  archived?: boolean;
  model?: string;
  reasoningEffort?: 'minimal' | 'low' | 'medium' | 'high';
}
