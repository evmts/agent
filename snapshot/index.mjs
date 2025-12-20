/**
 * ESM wrapper for the native jj bindings
 * The native bindings are generated as CommonJS, so we use createRequire to load them
 */

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const require = createRequire(import.meta.url);

// Load the CommonJS native binding
const native = require('./index.js');

export const JjWorkspace = native.JjWorkspace;
export const isJjWorkspace = native.isJjWorkspace;
export const isGitRepo = native.isGitRepo;
