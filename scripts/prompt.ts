#!/usr/bin/env bun
/**
 * Feature Implementation Pipeline
 *
 * Loops through all feature prompts, implementing them one by one with:
 * - Implementation agent
 * - Validation (lint, typecheck, build)
 * - Review agent with structured feedback
 * - Iteration based on review
 * - LRU context of recent reports
 */

import Anthropic from "@anthropic-ai/sdk";
import { readdir, readFile, writeFile, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { join } from "path";
import { $ } from "bun";

// ============================================================================
// Configuration
// ============================================================================

const CONFIG = {
  promptsDir: join(import.meta.dir, "../docs/prompts"),
  reportsDir: join(import.meta.dir, "../reports"),
  model: "claude-sonnet-4-20250514",
  maxIterations: 3, // Max review iterations per feature
  lruSize: 5, // Number of recent reports to include in context
};

// ============================================================================
// Types
// ============================================================================

interface FeaturePrompt {
  filename: string;
  index: number;
  name: string;
  content: string;
}

interface ImplementationReport {
  feature: string;
  timestamp: string;
  iteration: number;
  summary: string;
  filesModified: string[];
  filesCreated: string[];
  testsAdded: string[];
  notes: string;
}

interface ReviewResponse {
  complete: boolean;
  score: number; // 1-10
  issues: string[];
  suggestions: string[];
  mustFix: string[];
}

interface ValidationResult {
  success: boolean;
  lintErrors: string | null;
  typeErrors: string | null;
  buildErrors: string | null;
}

// ============================================================================
// LRU Cache for Recent Reports
// ============================================================================

class LRUCache<T> {
  private cache: Map<string, T> = new Map();
  private maxSize: number;

  constructor(maxSize: number) {
    this.maxSize = maxSize;
  }

  set(key: string, value: T): void {
    if (this.cache.has(key)) {
      this.cache.delete(key);
    } else if (this.cache.size >= this.maxSize) {
      const firstKey = this.cache.keys().next().value;
      if (firstKey) this.cache.delete(firstKey);
    }
    this.cache.set(key, value);
  }

  get(key: string): T | undefined {
    const value = this.cache.get(key);
    if (value !== undefined) {
      this.cache.delete(key);
      this.cache.set(key, value);
    }
    return value;
  }

  getAll(): T[] {
    return Array.from(this.cache.values());
  }

  getAllWithKeys(): Array<{ key: string; value: T }> {
    return Array.from(this.cache.entries()).map(([key, value]) => ({
      key,
      value,
    }));
  }
}

// ============================================================================
// Claude API Client
// ============================================================================

const anthropic = new Anthropic();

async function runAgent(
  systemPrompt: string,
  userPrompt: string,
  tools?: Anthropic.Tool[]
): Promise<string> {
  const messages: Anthropic.MessageParam[] = [
    { role: "user", content: userPrompt },
  ];

  let response = await anthropic.messages.create({
    model: CONFIG.model,
    max_tokens: 16384,
    system: systemPrompt,
    messages,
    tools,
  });

  // Handle tool use in agentic loop
  while (response.stop_reason === "tool_use") {
    const toolUseBlocks = response.content.filter(
      (block): block is Anthropic.ToolUseBlock => block.type === "tool_use"
    );

    const toolResults: Anthropic.ToolResultBlockParam[] = [];

    for (const toolUse of toolUseBlocks) {
      const result = await executeToolCall(toolUse.name, toolUse.input as Record<string, unknown>);
      toolResults.push({
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: result,
      });
    }

    messages.push({ role: "assistant", content: response.content });
    messages.push({ role: "user", content: toolResults });

    response = await anthropic.messages.create({
      model: CONFIG.model,
      max_tokens: 16384,
      system: systemPrompt,
      messages,
      tools,
    });
  }

  // Extract text from response
  const textBlocks = response.content.filter(
    (block): block is Anthropic.TextBlock => block.type === "text"
  );

  return textBlocks.map((b) => b.text).join("\n");
}

// ============================================================================
// Tool Execution
// ============================================================================

async function executeToolCall(
  name: string,
  input: Record<string, unknown>
): Promise<string> {
  try {
    switch (name) {
      case "read_file": {
        const path = input.path as string;
        const content = await readFile(path, "utf-8");
        return content;
      }

      case "write_file": {
        const path = input.path as string;
        const content = input.content as string;
        const dir = join(path, "..");
        if (!existsSync(dir)) {
          await mkdir(dir, { recursive: true });
        }
        await writeFile(path, content);
        return `File written: ${path}`;
      }

      case "list_files": {
        const path = input.path as string;
        const pattern = input.pattern as string | undefined;
        const result = await $`find ${path} -type f ${pattern ? `-name "${pattern}"` : ""} | head -100`.text();
        return result;
      }

      case "run_command": {
        const command = input.command as string;
        const cwd = (input.cwd as string) || process.cwd();
        const result = await $`cd ${cwd} && ${command}`.text();
        return result;
      }

      case "search_code": {
        const pattern = input.pattern as string;
        const path = (input.path as string) || ".";
        const result = await $`grep -rn "${pattern}" ${path} --include="*.ts" --include="*.tsx" --include="*.astro" | head -50`.text();
        return result || "No matches found";
      }

      default:
        return `Unknown tool: ${name}`;
    }
  } catch (error) {
    return `Error: ${error instanceof Error ? error.message : String(error)}`;
  }
}

// ============================================================================
// Tools Definition
// ============================================================================

const implementationTools: Anthropic.Tool[] = [
  {
    name: "read_file",
    description: "Read a file from the filesystem",
    input_schema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "Absolute path to the file" },
      },
      required: ["path"],
    },
  },
  {
    name: "write_file",
    description: "Write content to a file",
    input_schema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "Absolute path to the file" },
        content: { type: "string", description: "Content to write" },
      },
      required: ["path", "content"],
    },
  },
  {
    name: "list_files",
    description: "List files in a directory",
    input_schema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "Directory path" },
        pattern: { type: "string", description: "Optional glob pattern" },
      },
      required: ["path"],
    },
  },
  {
    name: "run_command",
    description: "Run a shell command",
    input_schema: {
      type: "object" as const,
      properties: {
        command: { type: "string", description: "Command to run" },
        cwd: { type: "string", description: "Working directory" },
      },
      required: ["command"],
    },
  },
  {
    name: "search_code",
    description: "Search for code patterns in the codebase",
    input_schema: {
      type: "object" as const,
      properties: {
        pattern: { type: "string", description: "Search pattern (regex)" },
        path: { type: "string", description: "Directory to search in" },
      },
      required: ["pattern"],
    },
  },
];

// ============================================================================
// Feature Loading
// ============================================================================

async function loadFeaturePrompts(): Promise<FeaturePrompt[]> {
  const files = await readdir(CONFIG.promptsDir);
  const prompts: FeaturePrompt[] = [];

  for (const file of files.sort()) {
    if (!file.endsWith(".md")) continue;

    const match = file.match(/^(\d+)_(.+)\.md$/);
    if (!match) continue;

    const content = await readFile(join(CONFIG.promptsDir, file), "utf-8");
    prompts.push({
      filename: file,
      index: parseInt(match[1], 10),
      name: match[2].replace(/_/g, " "),
      content,
    });
  }

  return prompts;
}

// ============================================================================
// Validation
// ============================================================================

async function runValidation(): Promise<ValidationResult> {
  const result: ValidationResult = {
    success: true,
    lintErrors: null,
    typeErrors: null,
    buildErrors: null,
  };

  const projectRoot = join(import.meta.dir, "..");

  // Run linter
  try {
    await $`cd ${projectRoot} && bun run lint 2>&1`.text();
  } catch (error) {
    result.success = false;
    result.lintErrors = error instanceof Error ? error.message : String(error);
  }

  // Run typecheck
  try {
    await $`cd ${projectRoot} && bun run typecheck 2>&1`.text();
  } catch (error) {
    result.success = false;
    result.typeErrors = error instanceof Error ? error.message : String(error);
  }

  // Run build
  try {
    await $`cd ${projectRoot} && bun run build 2>&1`.text();
  } catch (error) {
    result.success = false;
    result.buildErrors = error instanceof Error ? error.message : String(error);
  }

  return result;
}

// ============================================================================
// Report Management
// ============================================================================

async function writeReport(
  feature: string,
  iteration: number,
  report: ImplementationReport
): Promise<string> {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `${feature}_iter${iteration}_${timestamp}.json`;
  const path = join(CONFIG.reportsDir, filename);

  if (!existsSync(CONFIG.reportsDir)) {
    await mkdir(CONFIG.reportsDir, { recursive: true });
  }

  await writeFile(path, JSON.stringify(report, null, 2));
  return path;
}

async function writeReviewReport(
  feature: string,
  iteration: number,
  review: ReviewResponse
): Promise<string> {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `${feature}_review${iteration}_${timestamp}.json`;
  const path = join(CONFIG.reportsDir, filename);

  await writeFile(path, JSON.stringify(review, null, 2));
  return path;
}

// ============================================================================
// Implementation Agent
// ============================================================================

async function runImplementationAgent(
  feature: FeaturePrompt,
  iteration: number,
  previousFeedback: string | null,
  recentReports: string
): Promise<ImplementationReport> {
  const projectRoot = join(import.meta.dir, "..");

  const systemPrompt = `You are an expert software engineer implementing features for Plue, a GitHub clone built with:
- Runtime: Bun (not Node.js)
- Frontend: Astro v5 (SSR)
- Backend: Hono server
- Database: PostgreSQL
- Validation: Zod v4

Your task is to implement the feature described in the prompt. Follow these rules:

1. READ the existing codebase first to understand patterns
2. Make incremental, focused changes
3. Follow existing code conventions
4. Add proper TypeScript types
5. Include error handling
6. VALIDATE your changes work by checking file contents after writing
7. DO NOT modify files in scripts/ directory - those are infrastructure

Project root: ${projectRoot}

Key directories:
- ui/pages/ - Astro pages
- ui/components/ - Astro components
- ui/lib/ - Frontend utilities
- server/routes/ - Hono API routes
- server/middleware/ - Hono middleware
- db/ - Database schema and queries
- core/ - Core business logic

IMPORTANT: After making changes, verify they are correct. Read back files you wrote to confirm.

At the end, provide a summary in this exact format:
---REPORT---
{
  "summary": "Brief description of what was implemented",
  "filesModified": ["list", "of", "modified", "files"],
  "filesCreated": ["list", "of", "new", "files"],
  "testsAdded": ["list", "of", "test", "files"],
  "notes": "Any important notes or caveats"
}
---END REPORT---`;

  let userPrompt = `# Feature to Implement: ${feature.name}

## Implementation Prompt:
${feature.content}

## Recent Implementation Context:
${recentReports || "This is the first feature being implemented."}
`;

  if (previousFeedback) {
    userPrompt += `
## Review Feedback (Iteration ${iteration}):
The previous implementation was reviewed and needs these changes:
${previousFeedback}

Please address ALL the issues mentioned above.
`;
  }

  userPrompt += `
## Instructions:
1. First, explore the codebase to understand existing patterns
2. Implement the feature following the prompt
3. Verify your changes by reading back the files
4. Provide a report in the format specified above

Begin implementation.`;

  console.log(`  Running implementation agent (iteration ${iteration})...`);
  const response = await runAgent(systemPrompt, userPrompt, implementationTools);

  // Parse report from response
  const reportMatch = response.match(/---REPORT---\s*([\s\S]*?)\s*---END REPORT---/);
  let reportData: Partial<ImplementationReport> = {};

  if (reportMatch) {
    try {
      reportData = JSON.parse(reportMatch[1]);
    } catch {
      console.warn("  Warning: Could not parse report JSON, using defaults");
    }
  }

  return {
    feature: feature.name,
    timestamp: new Date().toISOString(),
    iteration,
    summary: reportData.summary || "Implementation completed",
    filesModified: reportData.filesModified || [],
    filesCreated: reportData.filesCreated || [],
    testsAdded: reportData.testsAdded || [],
    notes: reportData.notes || response.slice(0, 500),
  };
}

// ============================================================================
// Review Agent
// ============================================================================

async function runReviewAgent(
  feature: FeaturePrompt,
  implementationReport: ImplementationReport
): Promise<ReviewResponse> {
  const projectRoot = join(import.meta.dir, "..");

  const systemPrompt = `You are a senior code reviewer evaluating a feature implementation for Plue.

Your job is to:
1. Check if the implementation matches the feature requirements
2. Verify code quality and patterns
3. Look for bugs or issues
4. Ensure proper error handling
5. Check for security concerns

Project root: ${projectRoot}

Be thorough but fair. Only flag real issues.

You MUST respond with ONLY a JSON object in this exact format:
{
  "complete": true/false,
  "score": 1-10,
  "issues": ["list of issues found"],
  "suggestions": ["optional improvements"],
  "mustFix": ["critical issues that must be fixed before approval"]
}

If complete is false, mustFix must have at least one item.`;

  const userPrompt = `# Review: ${feature.name}

## Original Requirements:
${feature.content}

## Implementation Report:
${JSON.stringify(implementationReport, null, 2)}

## Your Task:
1. Read the files that were modified/created
2. Verify they implement the feature correctly
3. Check for bugs, issues, or missing pieces
4. Provide your assessment as JSON

Review the implementation now.`;

  console.log(`  Running review agent...`);
  const response = await runAgent(systemPrompt, userPrompt, implementationTools);

  // Parse JSON response
  const jsonMatch = response.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    console.warn("  Warning: Could not parse review JSON, assuming incomplete");
    return {
      complete: false,
      score: 5,
      issues: ["Could not parse review response"],
      suggestions: [],
      mustFix: ["Review agent response was not valid JSON"],
    };
  }

  try {
    return JSON.parse(jsonMatch[0]) as ReviewResponse;
  } catch {
    return {
      complete: false,
      score: 5,
      issues: ["Invalid JSON in review response"],
      suggestions: [],
      mustFix: ["Review agent response was malformed"],
    };
  }
}

// ============================================================================
// Fix Agent
// ============================================================================

async function runFixAgent(validation: ValidationResult): Promise<void> {
  const projectRoot = join(import.meta.dir, "..");

  const systemPrompt = `You are a senior engineer fixing build/lint/type errors in a TypeScript project.

Project root: ${projectRoot}

Fix all errors while maintaining code quality. Don't just suppress errors - fix them properly.

IMPORTANT: Do NOT modify files in the scripts/ directory - those are infrastructure files.`;

  const errors: string[] = [];
  if (validation.lintErrors) errors.push(`Lint errors:\n${validation.lintErrors}`);
  if (validation.typeErrors) errors.push(`Type errors:\n${validation.typeErrors}`);
  if (validation.buildErrors) errors.push(`Build errors:\n${validation.buildErrors}`);

  const userPrompt = `Fix these errors:

${errors.join("\n\n")}

Read the relevant files, understand the issues, and fix them. Do NOT touch scripts/ directory.`;

  console.log(`  Running fix agent...`);
  await runAgent(systemPrompt, userPrompt, implementationTools);
}

// ============================================================================
// Main Pipeline
// ============================================================================

async function main() {
  console.log("=".repeat(60));
  console.log("Plue Feature Implementation Pipeline");
  console.log("=".repeat(60));

  // Initialize
  const features = await loadFeaturePrompts();
  const reportCache = new LRUCache<ImplementationReport>(CONFIG.lruSize);

  console.log(`\nLoaded ${features.length} features to implement:\n`);
  for (const f of features) {
    console.log(`  ${f.index.toString().padStart(2, "0")}. ${f.name}`);
  }
  console.log("");

  // Process each feature
  for (const feature of features) {
    console.log("=".repeat(60));
    console.log(`Feature ${feature.index}: ${feature.name}`);
    console.log("=".repeat(60));

    let iteration = 1;
    let complete = false;
    let previousFeedback: string | null = null;

    while (!complete && iteration <= CONFIG.maxIterations) {
      console.log(`\nIteration ${iteration}/${CONFIG.maxIterations}`);

      // Build recent reports context
      const recentReports = reportCache
        .getAllWithKeys()
        .map(({ key, value }) => `### ${key}\n${value.summary}\nFiles: ${value.filesModified.join(", ")}`)
        .join("\n\n");

      // Run implementation
      const report = await runImplementationAgent(
        feature,
        iteration,
        previousFeedback,
        recentReports
      );

      // Save report
      const reportPath = await writeReport(feature.name, iteration, report);
      console.log(`  Report saved: ${reportPath}`);
      reportCache.set(feature.name, report);

      // Run validation
      console.log(`  Running validation...`);
      let validation = await runValidation();

      // Fix if needed
      if (!validation.success) {
        console.log(`  Validation failed, running fix agent...`);
        await runFixAgent(validation);

        // Re-validate
        validation = await runValidation();
        if (!validation.success) {
          console.log(`  Warning: Fix agent could not resolve all issues`);
        }
      }

      // Run review
      const review = await runReviewAgent(feature, report);
      const reviewPath = await writeReviewReport(feature.name, iteration, review);
      console.log(`  Review saved: ${reviewPath}`);
      console.log(`  Review score: ${review.score}/10, Complete: ${review.complete}`);

      if (review.complete && validation.success) {
        complete = true;
        console.log(`  ✓ Feature ${feature.name} completed!`);
      } else {
        // Build feedback for next iteration
        const feedbackParts: string[] = [];

        if (review.mustFix.length > 0) {
          feedbackParts.push(`Must fix:\n${review.mustFix.map((f) => `- ${f}`).join("\n")}`);
        }
        if (review.issues.length > 0) {
          feedbackParts.push(`Issues:\n${review.issues.map((i) => `- ${i}`).join("\n")}`);
        }
        if (!validation.success) {
          feedbackParts.push(`Validation errors:\n- Lint: ${validation.lintErrors || "OK"}\n- Types: ${validation.typeErrors || "OK"}\n- Build: ${validation.buildErrors || "OK"}`);
        }

        previousFeedback = feedbackParts.join("\n\n");
        iteration++;
      }
    }

    if (!complete) {
      console.log(`  ⚠ Feature ${feature.name} incomplete after ${CONFIG.maxIterations} iterations`);
    }

    console.log("");
  }

  // Final summary
  console.log("=".repeat(60));
  console.log("Pipeline Complete");
  console.log("=".repeat(60));
  console.log(`\nReports written to: ${CONFIG.reportsDir}`);
}

// ============================================================================
// Entry Point
// ============================================================================

main().catch((error) => {
  console.error("Pipeline failed:", error);
  process.exit(1);
});
