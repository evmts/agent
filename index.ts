/**
 * Agent Server Entry Point
 *
 * Starts the agent server using Bun.serve() with Hono.
 *
 * Usage:
 *   bun run index.ts
 *
 * Environment Variables:
 *   ANTHROPIC_API_KEY - Required: Claude API key
 *   HOST - Server host (default: 0.0.0.0)
 *   PORT - Server port (default: 8000)
 *   WORKING_DIR - Working directory (default: cwd)
 */

import { app } from './server';

// Constants
const DEFAULT_HOST = '0.0.0.0';
const DEFAULT_PORT = 8000;

// Get configuration from environment
const host = process.env.HOST ?? DEFAULT_HOST;
const port = parseInt(process.env.PORT ?? String(DEFAULT_PORT), 10);
const workingDir = process.env.WORKING_DIR ?? process.cwd();

// Validate API key
if (!process.env.ANTHROPIC_API_KEY) {
  console.error('Error: ANTHROPIC_API_KEY environment variable is required');
  process.exit(1);
}

console.log('Starting agent server...');
console.log(`  Host: ${host}`);
console.log(`  Port: ${port}`);
console.log(`  Working directory: ${workingDir}`);
console.log('');

// Start server using Bun.serve()
const server = Bun.serve({
  hostname: host,
  port,
  fetch: app.fetch,
});

console.log(`Agent server listening on http://${server.hostname}:${server.port}`);

// Export for programmatic use
export { app, server };

// Re-export core and agent modules
export * from './core';
export * from './ai';
export * from './server';
