import { JjWorkspace, isJjWorkspace, isGitRepo } from './index.js';

// Test the helper functions
console.log('Testing jj-native bindings...\n');

// Check if current directory is a jj workspace
const cwd = process.cwd();
console.log(`Current directory: ${cwd}`);
console.log(`Is jj workspace: ${isJjWorkspace(cwd)}`);
console.log(`Is git repo: ${isGitRepo(cwd)}`);

// Test creating a new workspace
const testDir = '/tmp/jj-test-' + Date.now();
console.log(`\nCreating test workspace at: ${testDir}`);

try {
  // Create directory first
  await Bun.$`mkdir -p ${testDir}`;

  // Initialize a new jj workspace
  const workspace = JjWorkspace.init(testDir);
  console.log(`Workspace root: ${workspace.root}`);
  console.log(`Repo path: ${workspace.repoPath}`);

  // Get root commit
  const rootCommit = workspace.getRootCommit();
  console.log(`\nRoot commit:`);
  console.log(`  ID: ${rootCommit.id.substring(0, 12)}...`);
  console.log(`  Change ID: ${rootCommit.changeId.substring(0, 12)}...`);
  console.log(`  Description: "${rootCommit.description || '(empty)'}"`);
  console.log(`  Is empty: ${rootCommit.isEmpty}`);

  // Get current operation
  const op = workspace.getCurrentOperation();
  console.log(`\nCurrent operation:`);
  console.log(`  ID: ${op.id.substring(0, 12)}...`);
  console.log(`  Description: ${op.description}`);

  // List heads
  const heads = workspace.listHeads();
  console.log(`\nHeads: ${heads.length} commit(s)`);
  for (const head of heads) {
    console.log(`  - ${head.substring(0, 12)}...`);
  }

  // List bookmarks
  const bookmarks = workspace.listBookmarks();
  console.log(`\nBookmarks: ${bookmarks.length}`);
  for (const bookmark of bookmarks) {
    console.log(`  - ${bookmark.name} (${bookmark.isLocal ? 'local' : 'remote'})`);
  }

  console.log('\n✅ All tests passed!');

  // Cleanup
  await Bun.$`rm -rf ${testDir}`;
  console.log(`\nCleaned up test directory.`);
} catch (error) {
  console.error('Error:', error);
  process.exit(1);
}
