/**
 * Message models - user and assistant messages in a session.
 */

export type MessageStatus = 'pending' | 'streaming' | 'completed' | 'failed' | 'aborted';

export interface MessageTime {
  created: number;
  completed?: number;
}

export interface ModelInfo {
  providerID: string;
  modelID: string;
}

export interface PathInfo {
  cwd: string;
  root: string;
}

export interface TokenInfo {
  input: number;
  output: number;
  reasoning: number;
  cache?: {
    read: number;
    write: number;
  };
}

export interface UserMessage {
  id: string;
  sessionID: string;
  role: 'user';
  time: MessageTime;
  status: MessageStatus;
  thinkingText?: string;
  errorMessage?: string;
  agent: string;
  model: ModelInfo;
  system?: string;
  tools?: Record<string, boolean>;
}

export interface AssistantMessage {
  id: string;
  sessionID: string;
  role: 'assistant';
  time: MessageTime;
  status: MessageStatus;
  thinkingText?: string;
  errorMessage?: string;
  parentID: string;
  modelID: string;
  providerID: string;
  mode: string;
  path: PathInfo;
  cost: number;
  tokens: TokenInfo;
  finish?: string;
  summary?: boolean;
  error?: Record<string, unknown>;
}

export type Message = UserMessage | AssistantMessage;

export function isUserMessage(msg: Message): msg is UserMessage {
  return msg.role === 'user';
}

export function isAssistantMessage(msg: Message): msg is AssistantMessage {
  return msg.role === 'assistant';
}
