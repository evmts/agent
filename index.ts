/**
 * Agent Server Entry Point
 *
 * Starts the agent server with Node.js.
 *
 * Usage:
 *   npm start
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

console.log('Starting agent server...');
console.log(`  Host: ${host}`);
console.log(`  Port: ${port}`);
console.log(`  Working directory: ${workingDir}`);
console.log('');

// For Node.js environment, we'll need to use a different server
console.log(`Agent server configured for http://${host}:${port}`);

// Export for programmatic use
export { app };

// Re-export core modules
export * from './core';