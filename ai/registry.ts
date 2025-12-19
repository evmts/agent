/**
 * Agent registry - configurations for different agent types.
 *
 * Defines agent configs for different use cases:
 * - build: Primary agent with full tool access
 * - general: Subagent for parallel task execution
 * - explore: Read-only for codebase search
 * - plan: Analysis and planning without file writes
 */

import type { AgentToolName } from './tools';

export type AgentMode = 'primary' | 'subagent';

export interface AgentConfig {
  name: string;
  description: string;
  mode: AgentMode;
  systemPrompt: string;
  temperature: number;
  topP: number;
  /** Tools enabled for this agent (true = enabled, false = disabled) */
  toolsEnabled: Partial<Record<AgentToolName | string, boolean>>;
  /** Shell command patterns allowed (glob patterns) */
  allowedShellPatterns?: string[];
}

// Default system prompt prefix
const SYSTEM_PROMPT_PREFIX = `You are an AI assistant helping with software development tasks.
You have access to tools for reading, writing, and searching files.

Key principles:
- Always read files before modifying them
- Make minimal, targeted changes
- Explain your reasoning before making changes
- Ask for clarification when requirements are unclear
`;

// Agent configurations
const buildAgent: AgentConfig = {
  name: 'build',
  description: 'Primary agent with full tool access for development tasks',
  mode: 'primary',
  systemPrompt: `${SYSTEM_PROMPT_PREFIX}
You are the primary development agent. You have full access to all tools
and can read, write, and modify files as needed to complete tasks.

You can interact with GitHub using the github tool for:
- Creating and viewing pull requests
- Cloning and syncing repositories
- Creating and viewing issues
- Checking CI/CD status
`,
  temperature: 0.7,
  topP: 0.95,
  toolsEnabled: {
    grep: true,
    readFile: true,
    writeFile: true,
    multiedit: true,
    webFetch: true,
    github: true,
  },
  allowedShellPatterns: ['*'], // All commands allowed
};

const generalAgent: AgentConfig = {
  name: 'general',
  description: 'Subagent for parallel task execution',
  mode: 'subagent',
  systemPrompt: `${SYSTEM_PROMPT_PREFIX}
You are a general-purpose subagent executing a specific task.
Focus on completing your assigned objective efficiently.
`,
  temperature: 0.7,
  topP: 0.95,
  toolsEnabled: {
    grep: true,
    readFile: true,
    writeFile: true,
    multiedit: true,
    webFetch: true,
    github: true,
  },
  allowedShellPatterns: ['*'],
};

const exploreAgent: AgentConfig = {
  name: 'explore',
  description: 'Read-only agent for fast codebase exploration',
  mode: 'subagent',
  systemPrompt: `${SYSTEM_PROMPT_PREFIX}
You are an exploration agent focused on searching and understanding code.
You can only read files and search - you cannot modify anything.
Be thorough but efficient in your search.
`,
  temperature: 0.5,
  topP: 0.9,
  toolsEnabled: {
    grep: true,
    readFile: true,
    writeFile: false,
    multiedit: false,
    webFetch: false,
  },
  allowedShellPatterns: [
    'ls *',
    'find *',
    'tree *',
    'git log *',
    'git show *',
    'git diff *',
    'git status',
  ],
};

const planAgent: AgentConfig = {
  name: 'plan',
  description: 'Analysis and planning agent (read-only)',
  mode: 'subagent',
  systemPrompt: `${SYSTEM_PROMPT_PREFIX}
You are a planning agent. Analyze the codebase and create implementation plans.
You can read files and search but cannot modify anything.
Focus on understanding architecture and proposing clear, actionable plans.
`,
  temperature: 0.6,
  topP: 0.9,
  toolsEnabled: {
    grep: true,
    readFile: true,
    writeFile: false,
    multiedit: false,
    webFetch: true, // Can fetch documentation
  },
  allowedShellPatterns: [
    'ls *',
    'find *',
    'tree *',
    'git *',
    'cat *',
  ],
};

// Registry map
const agentRegistry = new Map<string, AgentConfig>([
  ['build', buildAgent],
  ['general', generalAgent],
  ['explore', exploreAgent],
  ['plan', planAgent],
]);

/**
 * Get agent configuration by name.
 */
export function getAgentConfig(name: string): AgentConfig {
  const config = agentRegistry.get(name);
  if (!config) {
    // Fall back to build agent
    return buildAgent;
  }
  return config;
}

/**
 * Check if a tool is enabled for an agent.
 */
export function isToolEnabled(agentName: string, toolName: string): boolean {
  const config = getAgentConfig(agentName);
  const enabled = config.toolsEnabled[toolName as AgentToolName];
  // Default to true if not specified
  return enabled !== false;
}

/**
 * Check if a shell command is allowed for an agent.
 */
export function isShellCommandAllowed(agentName: string, command: string): boolean {
  const config = getAgentConfig(agentName);
  const patterns = config.allowedShellPatterns;

  if (!patterns || patterns.length === 0) {
    return false;
  }

  // Check for wildcard pattern
  if (patterns.includes('*')) {
    return true;
  }

  // Simple glob matching
  for (const pattern of patterns) {
    if (matchGlob(pattern, command)) {
      return true;
    }
  }

  return false;
}

/**
 * Simple glob pattern matching.
 */
function matchGlob(pattern: string, text: string): boolean {
  // Convert glob to regex
  const regexPattern = pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&') // Escape special chars
    .replace(/\*/g, '.*') // * -> .*
    .replace(/\?/g, '.'); // ? -> .

  const regex = new RegExp(`^${regexPattern}$`, 'i');
  return regex.test(text);
}

/**
 * List all registered agent names.
 */
export function listAgentNames(): string[] {
  return Array.from(agentRegistry.keys());
}

/**
 * Register a custom agent configuration.
 */
export function registerAgent(config: AgentConfig): void {
  agentRegistry.set(config.name, config);
}

export { buildAgent, generalAgent, exploreAgent, planAgent };
