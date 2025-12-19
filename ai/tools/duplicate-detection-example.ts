/**
 * Example demonstrating duplicate tool call detection.
 *
 * Run with: bun run ai/tools/duplicate-detection-example.ts
 */

import { getToolCallTracker } from './index';

console.log('=== Duplicate Tool Call Detection Example ===\n');

const tracker = getToolCallTracker();
const sessionId = 'example-session';

// Example 1: Reading the same file multiple times
console.log('Example 1: Reading the same file twice');
console.log('----------------------------------------');

// First read
console.log('1. First read of package.json...');
const check1 = tracker.checkDuplicate(sessionId, 'readFile', {
  filePath: '/Users/williamcory/plue/package.json',
});
console.log('   Is duplicate?', check1.isDuplicate); // false

tracker.recordCall(
  sessionId,
  'readFile',
  { filePath: '/Users/williamcory/plue/package.json' },
  '{\n  "name": "plue",\n  "version": "1.0.0"\n}'
);

// Second read (duplicate!)
console.log('2. Second read of package.json...');
const check2 = tracker.checkDuplicate(sessionId, 'readFile', {
  filePath: '/Users/williamcory/plue/package.json',
});
console.log('   Is duplicate?', check2.isDuplicate); // true
console.log('   Cached result:', check2.previousResult?.substring(0, 50) + '...');
console.log();

// Example 2: Different files are not duplicates
console.log('Example 2: Different files are not duplicates');
console.log('---------------------------------------------');

console.log('3. Reading a different file (README.md)...');
const check3 = tracker.checkDuplicate(sessionId, 'readFile', {
  filePath: '/Users/williamcory/plue/README.md',
});
console.log('   Is duplicate?', check3.isDuplicate); // false
console.log();

// Example 3: Grep queries
console.log('Example 3: Grep queries');
console.log('-----------------------');

console.log('4. First grep for "export"...');
tracker.recordCall(
  sessionId,
  'grep',
  {
    pattern: 'export',
    path: '/Users/williamcory/plue/ai',
    glob: '*.ts',
  },
  'Found 42 matches in 8 files'
);

console.log('5. Same grep query...');
const check4 = tracker.checkDuplicate(sessionId, 'grep', {
  pattern: 'export',
  path: '/Users/williamcory/plue/ai',
  glob: '*.ts',
});
console.log('   Is duplicate?', check4.isDuplicate); // true
console.log('   Cached result:', check4.previousResult);

console.log('6. Different pattern...');
const check5 = tracker.checkDuplicate(sessionId, 'grep', {
  pattern: 'import',
  path: '/Users/williamcory/plue/ai',
  glob: '*.ts',
});
console.log('   Is duplicate?', check5.isDuplicate); // false
console.log();

// Example 4: Tools that never cache
console.log('Example 4: Exec commands never cache');
console.log('------------------------------------');

console.log('7. First exec of "ls"...');
tracker.recordCall(
  sessionId,
  'unifiedExec',
  { command: 'ls -la' },
  'total 48\ndrwxr-xr-x  12 user  staff  384 Dec 19 12:00 .\n...'
);

console.log('8. Same exec command...');
const check6 = tracker.checkDuplicate(sessionId, 'unifiedExec', {
  command: 'ls -la',
});
console.log('   Is duplicate?', check6.isDuplicate); // false (never cache exec)
console.log('   Reason: Exec commands have side effects and should always run');
console.log();

// Example 5: Session isolation
console.log('Example 5: Sessions are isolated');
console.log('--------------------------------');

const session2 = 'different-session';

console.log('9. Reading package.json in a different session...');
const check7 = tracker.checkDuplicate(session2, 'readFile', {
  filePath: '/Users/williamcory/plue/package.json',
});
console.log('   Is duplicate?', check7.isDuplicate); // false (different session)
console.log('   Reason: Each session has independent history');
console.log();

// Example 6: Tracker statistics
console.log('Example 6: Tracker statistics');
console.log('-----------------------------');

const stats = tracker.getStats();
console.log('Total sessions:', stats.totalSessions);
console.log('Total calls:', stats.totalCalls);
console.log('Calls by tool:', JSON.stringify(stats.callsByTool, null, 2));
console.log();

// Example 7: Clearing session
console.log('Example 7: Clearing a session');
console.log('-----------------------------');

console.log('10. Before clearing session...');
const checkBefore = tracker.checkDuplicate(sessionId, 'readFile', {
  filePath: '/Users/williamcory/plue/package.json',
});
console.log('    Is duplicate?', checkBefore.isDuplicate); // true

tracker.clearSession(sessionId);

console.log('11. After clearing session...');
const checkAfter = tracker.checkDuplicate(sessionId, 'readFile', {
  filePath: '/Users/williamcory/plue/package.json',
});
console.log('    Is duplicate?', checkAfter.isDuplicate); // false (history cleared)
console.log();

console.log('=== Example Complete ===');
