/**
 * Tests for agent registry.
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import {
  getAgentConfig,
  isToolEnabled,
  isShellCommandAllowed,
  listAgentNames,
  registerAgent,
  buildAgent,
  generalAgent,
  exploreAgent,
  planAgent,
  type AgentConfig,
} from '../registry';

describe('getAgentConfig', () => {
  test('returns build agent config', () => {
    const config = getAgentConfig('build');
    expect(config.name).toBe('build');
    expect(config.mode).toBe('primary');
    expect(config.description).toContain('Primary agent');
    expect(config.temperature).toBe(0.7);
    expect(config.topP).toBe(0.95);
  });

  test('returns general agent config', () => {
    const config = getAgentConfig('general');
    expect(config.name).toBe('general');
    expect(config.mode).toBe('subagent');
    expect(config.description).toContain('parallel task');
  });

  test('returns explore agent config', () => {
    const config = getAgentConfig('explore');
    expect(config.name).toBe('explore');
    expect(config.mode).toBe('subagent');
    expect(config.description).toContain('Read-only');
    expect(config.temperature).toBe(0.5);
    expect(config.topP).toBe(0.9);
  });

  test('returns plan agent config', () => {
    const config = getAgentConfig('plan');
    expect(config.name).toBe('plan');
    expect(config.mode).toBe('subagent');
    expect(config.description).toContain('Analysis and planning');
    expect(config.temperature).toBe(0.6);
  });

  test('falls back to build agent for unknown name', () => {
    const config = getAgentConfig('nonexistent');
    expect(config.name).toBe('build');
    expect(config.mode).toBe('primary');
  });

  test('falls back to build agent for empty string', () => {
    const config = getAgentConfig('');
    expect(config.name).toBe('build');
  });

  test('falls back to build agent for null-like values', () => {
    const config1 = getAgentConfig(null as any);
    expect(config1.name).toBe('build');

    const config2 = getAgentConfig(undefined as any);
    expect(config2.name).toBe('build');
  });

  test('returns correct system prompts', () => {
    const buildConfig = getAgentConfig('build');
    expect(buildConfig.systemPrompt).toContain('primary development agent');
    expect(buildConfig.systemPrompt).toContain('full access to all tools');

    const exploreConfig = getAgentConfig('explore');
    expect(exploreConfig.systemPrompt).toContain('exploration agent');
    expect(exploreConfig.systemPrompt).toContain('only read files');

    const planConfig = getAgentConfig('plan');
    expect(planConfig.systemPrompt).toContain('planning agent');
    expect(planConfig.systemPrompt).toContain('Analyze the codebase');
  });
});

describe('isToolEnabled', () => {
  test('build agent has all tools enabled', () => {
    expect(isToolEnabled('build', 'grep')).toBe(true);
    expect(isToolEnabled('build', 'readFile')).toBe(true);
    expect(isToolEnabled('build', 'writeFile')).toBe(true);
    expect(isToolEnabled('build', 'multiedit')).toBe(true);
    expect(isToolEnabled('build', 'webFetch')).toBe(true);
    expect(isToolEnabled('build', 'github')).toBe(true);
  });

  test('general agent has all tools enabled', () => {
    expect(isToolEnabled('general', 'grep')).toBe(true);
    expect(isToolEnabled('general', 'readFile')).toBe(true);
    expect(isToolEnabled('general', 'writeFile')).toBe(true);
    expect(isToolEnabled('general', 'multiedit')).toBe(true);
    expect(isToolEnabled('general', 'webFetch')).toBe(true);
    expect(isToolEnabled('general', 'github')).toBe(true);
  });

  test('explore agent has limited tools', () => {
    expect(isToolEnabled('explore', 'grep')).toBe(true);
    expect(isToolEnabled('explore', 'readFile')).toBe(true);
    expect(isToolEnabled('explore', 'writeFile')).toBe(false);
    expect(isToolEnabled('explore', 'multiedit')).toBe(false);
    expect(isToolEnabled('explore', 'webFetch')).toBe(false);
  });

  test('plan agent has read and web tools', () => {
    expect(isToolEnabled('plan', 'grep')).toBe(true);
    expect(isToolEnabled('plan', 'readFile')).toBe(true);
    expect(isToolEnabled('plan', 'writeFile')).toBe(false);
    expect(isToolEnabled('plan', 'multiedit')).toBe(false);
    expect(isToolEnabled('plan', 'webFetch')).toBe(true);
  });

  test('defaults to true for unspecified tools', () => {
    expect(isToolEnabled('build', 'unknownTool')).toBe(true);
  });

  test('defaults to true for unknown agent', () => {
    expect(isToolEnabled('nonexistent', 'grep')).toBe(true);
    expect(isToolEnabled('nonexistent', 'writeFile')).toBe(true);
  });

  test('respects explicit false values', () => {
    expect(isToolEnabled('explore', 'writeFile')).toBe(false);
    expect(isToolEnabled('plan', 'multiedit')).toBe(false);
  });
});

describe('isShellCommandAllowed', () => {
  test('build agent allows all commands', () => {
    expect(isShellCommandAllowed('build', 'ls -la')).toBe(true);
    expect(isShellCommandAllowed('build', 'rm -rf /')).toBe(true);
    expect(isShellCommandAllowed('build', 'npm install')).toBe(true);
    expect(isShellCommandAllowed('build', 'git push')).toBe(true);
  });

  test('general agent allows all commands', () => {
    expect(isShellCommandAllowed('general', 'bun test')).toBe(true);
    expect(isShellCommandAllowed('general', 'docker build')).toBe(true);
  });

  test('explore agent allows only read-only commands', () => {
    expect(isShellCommandAllowed('explore', 'ls -la')).toBe(true);
    expect(isShellCommandAllowed('explore', 'find . -name "*.ts"')).toBe(true);
    expect(isShellCommandAllowed('explore', 'tree src')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git log --oneline')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git show HEAD')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git diff main')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git status')).toBe(true);
  });

  test('explore agent blocks write commands', () => {
    expect(isShellCommandAllowed('explore', 'rm file.ts')).toBe(false);
    expect(isShellCommandAllowed('explore', 'npm install')).toBe(false);
    expect(isShellCommandAllowed('explore', 'git commit')).toBe(false);
    expect(isShellCommandAllowed('explore', 'docker run')).toBe(false);
  });

  test('plan agent allows read and git commands', () => {
    expect(isShellCommandAllowed('plan', 'ls -la')).toBe(true);
    expect(isShellCommandAllowed('plan', 'find .')).toBe(true);
    expect(isShellCommandAllowed('plan', 'git log')).toBe(true);
    expect(isShellCommandAllowed('plan', 'git diff')).toBe(true);
    expect(isShellCommandAllowed('plan', 'cat package.json')).toBe(true);
  });

  test('plan agent blocks write commands', () => {
    expect(isShellCommandAllowed('plan', 'npm install')).toBe(false);
    expect(isShellCommandAllowed('plan', 'bun install')).toBe(false);
    expect(isShellCommandAllowed('plan', 'rm -rf')).toBe(false);
  });

  test('returns false for unknown agent with no patterns', () => {
    // Create a custom agent with no allowedShellPatterns
    const customConfig: AgentConfig = {
      name: 'custom',
      description: 'Custom agent',
      mode: 'subagent',
      systemPrompt: 'Custom prompt',
      temperature: 0.7,
      topP: 0.9,
      toolsEnabled: {},
    };
    registerAgent(customConfig);

    expect(isShellCommandAllowed('custom', 'ls')).toBe(false);
    expect(isShellCommandAllowed('custom', 'git status')).toBe(false);
  });

  test('returns false for agent with empty patterns array', () => {
    const customConfig: AgentConfig = {
      name: 'empty-patterns',
      description: 'Agent with empty patterns',
      mode: 'subagent',
      systemPrompt: 'Prompt',
      temperature: 0.7,
      topP: 0.9,
      toolsEnabled: {},
      allowedShellPatterns: [],
    };
    registerAgent(customConfig);

    expect(isShellCommandAllowed('empty-patterns', 'ls')).toBe(false);
  });

  test('handles case-insensitive pattern matching', () => {
    expect(isShellCommandAllowed('explore', 'GIT STATUS')).toBe(true);
    expect(isShellCommandAllowed('explore', 'Git Log --oneline')).toBe(true);
    expect(isShellCommandAllowed('explore', 'LS -LA')).toBe(true);
  });
});

describe('glob pattern matching', () => {
  test('matches simple wildcard patterns', () => {
    expect(isShellCommandAllowed('explore', 'ls -la')).toBe(true);
    expect(isShellCommandAllowed('explore', 'ls /path/to/dir')).toBe(true);
    expect(isShellCommandAllowed('explore', 'tree src')).toBe(true);
  });

  test('matches git commands with wildcards', () => {
    expect(isShellCommandAllowed('explore', 'git log --oneline')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git log origin/main')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git show HEAD~1')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git diff HEAD~5..HEAD')).toBe(true);
  });

  test('does not match unrelated commands', () => {
    expect(isShellCommandAllowed('explore', 'echo hello')).toBe(false);
    expect(isShellCommandAllowed('explore', 'npm test')).toBe(false);
    expect(isShellCommandAllowed('explore', 'bun run dev')).toBe(false);
  });

  test('handles special regex characters in commands', () => {
    expect(isShellCommandAllowed('explore', 'git log --format="%H"')).toBe(true);
    expect(isShellCommandAllowed('explore', 'find . -name "*.ts"')).toBe(true);
  });

  test('matches exact patterns without wildcards', () => {
    expect(isShellCommandAllowed('explore', 'git status')).toBe(true);
    expect(isShellCommandAllowed('explore', 'git status --short')).toBe(false);
  });
});

describe('listAgentNames', () => {
  test('returns all registered agent names', () => {
    const names = listAgentNames();
    expect(names).toContain('build');
    expect(names).toContain('general');
    expect(names).toContain('explore');
    expect(names).toContain('plan');
    expect(names.length).toBeGreaterThanOrEqual(4);
  });

  test('returns array of strings', () => {
    const names = listAgentNames();
    expect(Array.isArray(names)).toBe(true);
    for (const name of names) {
      expect(typeof name).toBe('string');
    }
  });
});

describe('registerAgent', () => {
  test('registers a custom agent', () => {
    const customAgent: AgentConfig = {
      name: 'test-agent',
      description: 'Test agent for unit tests',
      mode: 'subagent',
      systemPrompt: 'Test prompt',
      temperature: 0.5,
      topP: 0.8,
      toolsEnabled: {
        grep: true,
        readFile: true,
        writeFile: false,
      },
      allowedShellPatterns: ['echo *', 'cat *'],
    };

    registerAgent(customAgent);

    const retrieved = getAgentConfig('test-agent');
    expect(retrieved.name).toBe('test-agent');
    expect(retrieved.description).toBe('Test agent for unit tests');
    expect(retrieved.mode).toBe('subagent');
    expect(retrieved.temperature).toBe(0.5);
    expect(retrieved.topP).toBe(0.8);
  });

  test('registered agent respects tool permissions', () => {
    const customAgent: AgentConfig = {
      name: 'restricted',
      description: 'Restricted agent',
      mode: 'subagent',
      systemPrompt: 'Restricted',
      temperature: 0.7,
      topP: 0.9,
      toolsEnabled: {
        grep: true,
        writeFile: false,
        multiedit: false,
      },
    };

    registerAgent(customAgent);

    expect(isToolEnabled('restricted', 'grep')).toBe(true);
    expect(isToolEnabled('restricted', 'writeFile')).toBe(false);
    expect(isToolEnabled('restricted', 'multiedit')).toBe(false);
  });

  test('registered agent respects shell patterns', () => {
    const customAgent: AgentConfig = {
      name: 'shell-test',
      description: 'Shell test',
      mode: 'subagent',
      systemPrompt: 'Test',
      temperature: 0.7,
      topP: 0.9,
      toolsEnabled: {},
      allowedShellPatterns: ['bun test *', 'bun run *'],
    };

    registerAgent(customAgent);

    expect(isShellCommandAllowed('shell-test', 'bun test all')).toBe(true);
    expect(isShellCommandAllowed('shell-test', 'bun run dev')).toBe(true);
    expect(isShellCommandAllowed('shell-test', 'npm install')).toBe(false);
  });

  test('can override existing agents', () => {
    const originalBuild = getAgentConfig('build');
    expect(originalBuild.temperature).toBe(0.7);

    const customBuild: AgentConfig = {
      name: 'build',
      description: 'Modified build agent',
      mode: 'primary',
      systemPrompt: 'Modified',
      temperature: 0.9,
      topP: 0.99,
      toolsEnabled: {},
    };

    registerAgent(customBuild);

    const modifiedBuild = getAgentConfig('build');
    expect(modifiedBuild.temperature).toBe(0.9);
    expect(modifiedBuild.description).toBe('Modified build agent');

    // Restore original
    registerAgent(originalBuild);
  });

  test('newly registered agent appears in listAgentNames', () => {
    const before = listAgentNames();

    const newAgent: AgentConfig = {
      name: 'unique-test-agent',
      description: 'Unique',
      mode: 'subagent',
      systemPrompt: 'Test',
      temperature: 0.7,
      topP: 0.9,
      toolsEnabled: {},
    };

    registerAgent(newAgent);

    const after = listAgentNames();
    expect(after.length).toBe(before.length + 1);
    expect(after).toContain('unique-test-agent');
  });
});

describe('exported agent configs', () => {
  test('buildAgent matches getAgentConfig("build")', () => {
    const retrieved = getAgentConfig('build');
    expect(buildAgent.name).toBe(retrieved.name);
    expect(buildAgent.mode).toBe(retrieved.mode);
    expect(buildAgent.temperature).toBe(retrieved.temperature);
  });

  test('generalAgent matches getAgentConfig("general")', () => {
    const retrieved = getAgentConfig('general');
    expect(generalAgent.name).toBe(retrieved.name);
    expect(generalAgent.mode).toBe(retrieved.mode);
  });

  test('exploreAgent matches getAgentConfig("explore")', () => {
    const retrieved = getAgentConfig('explore');
    expect(exploreAgent.name).toBe(retrieved.name);
    expect(exploreAgent.mode).toBe(retrieved.mode);
  });

  test('planAgent matches getAgentConfig("plan")', () => {
    const retrieved = getAgentConfig('plan');
    expect(planAgent.name).toBe(retrieved.name);
    expect(planAgent.mode).toBe(retrieved.mode);
  });
});

describe('edge cases', () => {
  test('handles commands with only spaces', () => {
    expect(isShellCommandAllowed('explore', '   ')).toBe(false);
  });

  test('handles empty command string', () => {
    expect(isShellCommandAllowed('explore', '')).toBe(false);
  });

  test('handles very long commands', () => {
    const longCommand = 'ls ' + 'a'.repeat(10000);
    expect(isShellCommandAllowed('build', longCommand)).toBe(true);
  });

  test('handles special characters in tool names', () => {
    expect(isToolEnabled('build', 'tool-with-dash')).toBe(true);
    expect(isToolEnabled('build', 'tool_with_underscore')).toBe(true);
  });

  test('agent configs have required fields', () => {
    const configs = [buildAgent, generalAgent, exploreAgent, planAgent];

    for (const config of configs) {
      expect(config.name).toBeDefined();
      expect(typeof config.name).toBe('string');
      expect(config.description).toBeDefined();
      expect(typeof config.description).toBe('string');
      expect(config.mode).toBeDefined();
      expect(['primary', 'subagent']).toContain(config.mode);
      expect(config.systemPrompt).toBeDefined();
      expect(typeof config.systemPrompt).toBe('string');
      expect(typeof config.temperature).toBe('number');
      expect(typeof config.topP).toBe('number');
      expect(config.toolsEnabled).toBeDefined();
      expect(typeof config.toolsEnabled).toBe('object');
    }
  });

  test('temperature and topP values are in valid ranges', () => {
    const configs = [buildAgent, generalAgent, exploreAgent, planAgent];

    for (const config of configs) {
      expect(config.temperature).toBeGreaterThanOrEqual(0);
      expect(config.temperature).toBeLessThanOrEqual(2);
      expect(config.topP).toBeGreaterThan(0);
      expect(config.topP).toBeLessThanOrEqual(1);
    }
  });
});
