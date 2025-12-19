/**
 * Agent module exports.
 */

// Agent
export {
  streamAgent,
  runAgent,
  runAgentSync,
  persistedStreamAgent,
  type AgentOptions,
  type StreamEvent,
} from './agent';

// Wrapper
export {
  AgentWrapper,
  createAgentWrapper,
  type StreamOptions,
  type WrapperOptions,
  type TurnSummary,
  type FileDiff,
} from './wrapper';

// Registry
export {
  getAgentConfig,
  isToolEnabled,
  isShellCommandAllowed,
  listAgentNames,
  registerAgent,
  buildAgent,
  generalAgent,
  exploreAgent,
  planAgent,
  type AgentMode,
  type AgentConfig,
} from './registry';

// Tools
export {
  agentTools,
  grepTool,
  readFileTool,
  writeFileTool,
  multieditTool,
  webFetchTool,
  type AgentToolName,
} from './tools';
