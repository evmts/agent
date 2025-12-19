/**
 * Part models - components of messages (text, reasoning, tools, files).
 */

export interface PartTime {
  start: number;
  end?: number;
}

// Tool state discriminated union
export interface ToolStatePending {
  status: 'pending';
  input: Record<string, unknown>;
  raw: string;
}

export interface ToolStateRunning {
  status: 'running';
  input: Record<string, unknown>;
  title?: string;
  metadata?: Record<string, unknown>;
  time: PartTime;
}

export interface ToolStateCompleted {
  status: 'completed';
  input: Record<string, unknown>;
  output: string;
  title?: string;
  metadata?: Record<string, unknown>;
  time: PartTime;
}

export type ToolState = ToolStatePending | ToolStateRunning | ToolStateCompleted;

// Part types
export interface TextPart {
  id: string;
  sessionID: string;
  messageID: string;
  type: 'text';
  text: string;
  time?: PartTime;
}

export interface ReasoningPart {
  id: string;
  sessionID: string;
  messageID: string;
  type: 'reasoning';
  text: string;
  time: PartTime;
}

export interface ToolPart {
  id: string;
  sessionID: string;
  messageID: string;
  type: 'tool';
  tool: string;
  state: ToolState;
}

export interface FilePart {
  id: string;
  sessionID: string;
  messageID: string;
  type: 'file';
  mime: string;
  url: string;
  filename?: string;
}

export type Part = TextPart | ReasoningPart | ToolPart | FilePart;

// Type guards
export function isTextPart(part: Part): part is TextPart {
  return part.type === 'text';
}

export function isReasoningPart(part: Part): part is ReasoningPart {
  return part.type === 'reasoning';
}

export function isToolPart(part: Part): part is ToolPart {
  return part.type === 'tool';
}

export function isFilePart(part: Part): part is FilePart {
  return part.type === 'file';
}
