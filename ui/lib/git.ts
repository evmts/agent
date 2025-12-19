import { exec } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import type { TreeEntry, Commit } from "./types";

const execAsync = promisify(exec);

const REPOS_DIR = `${process.cwd()}/repos`;

async function run(cmd: string, cwd?: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd, { cwd });
    return stdout;
  } catch (error: unknown) {
    // Return empty string on error (e.g., empty repo)
    return (error as { stdout?: string })?.stdout || "";
  }
}

export async function initRepo(user: string, name: string): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  const tempDir = `/tmp/plue-init-${Date.now()}`;

  await mkdir(repoPath, { recursive: true });
  await run(`git init --bare "${repoPath}"`);

  // Create initial commit with README
  await mkdir(tempDir, { recursive: true });
  await run(`git init`, tempDir);
  await run(`git config user.email "plue@local"`, tempDir);
  await run(`git config user.name "Plue"`, tempDir);
  await writeFile(`${tempDir}/README.md`, `# ${name}\n\nA new repository.`);
  await run(`git add .`, tempDir);
  await run(`git commit -m "Initial commit"`, tempDir);
  await run(`git branch -M main`, tempDir);
  await run(`git remote add origin "${repoPath}"`, tempDir);
  await run(`git push -u origin main`, tempDir);
  await rm(tempDir, { recursive: true });
}

export async function deleteRepo(user: string, name: string): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  await rm(repoPath, { recursive: true });
}

export function getCloneUrl(user: string, name: string): string {
  return `file://${REPOS_DIR}/${user}/${name}`;
}

export async function listBranches(user: string, name: string): Promise<string[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const result = await run(`git branch --list`, repoPath);
    return result
      .trim()
      .split("\n")
      .map(b => b.replace("* ", "").trim())
      .filter(Boolean);
  } catch {
    return ["main"];
  }
}

export async function getTree(
  user: string,
  name: string,
  ref: string,
  path: string = ""
): Promise<TreeEntry[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const target = path ? `${ref}:${path}` : ref;
    const result = await run(`git ls-tree "${target}"`, repoPath);
    return parseGitLsTree(result);
  } catch {
    return [];
  }
}

export async function getFileContent(
  user: string,
  name: string,
  ref: string,
  path: string
): Promise<string | null> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const result = await run(`git show "${ref}:${path}"`, repoPath);
    return result;
  } catch {
    return null;
  }
}

export async function getCommits(
  user: string,
  name: string,
  ref: string,
  limit: number = 20
): Promise<Commit[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const format = "%H|%h|%an|%ae|%at|%s";
    const result = await run(`git log "${ref}" --format="${format}" -n ${limit}`, repoPath);
    return parseGitLog(result);
  } catch {
    return [];
  }
}

export async function repoExists(user: string, name: string): Promise<boolean> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  return existsSync(`${repoPath}/HEAD`);
}

function parseGitLsTree(output: string): TreeEntry[] {
  return output
    .trim()
    .split("\n")
    .filter(Boolean)
    .map(line => {
      const match = line.match(/^(\d+)\s+(blob|tree)\s+([a-f0-9]+)\t(.+)$/);
      if (!match) return null;
      const [, mode, type, hash, name] = match;
      return { mode, type: type as "blob" | "tree", hash, name };
    })
    .filter((entry): entry is TreeEntry => entry !== null);
}

function parseGitLog(output: string): Commit[] {
  return output
    .trim()
    .split("\n")
    .filter(Boolean)
    .map(line => {
      const parts = line.split("|");
      return {
        hash: parts[0] ?? '',
        shortHash: parts[1] ?? '',
        authorName: parts[2] ?? '',
        authorEmail: parts[3] ?? '',
        timestamp: parseInt(parts[4] ?? '0', 10) * 1000,
        message: parts.slice(5).join("|"),
      };
    });
}