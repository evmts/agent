import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { mkdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import {
  addDependency,
  removeDependency,
  getBlockingIssues,
  getBlockedByIssues,
  canCloseIssue,
} from "./git-issue-dependencies";
import {
  initIssuesRepo,
  createIssue,
  updateIssue,
  getIssue,
} from "./git-issues";

const TEST_USER = "testuser";
const TEST_REPO = "testrepo";
const REPOS_DIR = `${process.cwd()}/repos`;
const TEST_PATH = `${REPOS_DIR}/${TEST_USER}/${TEST_REPO}`;

describe("Issue Dependencies", () => {
  beforeEach(async () => {
    // Clean up test directory
    if (existsSync(TEST_PATH)) {
      await rm(TEST_PATH, { recursive: true });
    }
    await mkdir(TEST_PATH, { recursive: true });

    // Initialize issues repo
    await initIssuesRepo(TEST_USER, TEST_REPO);

    // Create test issues
    await createIssue(TEST_USER, TEST_REPO, {
      title: "Issue 1",
      body: "First issue",
      author: { id: 1, username: "testuser" },
    });

    await createIssue(TEST_USER, TEST_REPO, {
      title: "Issue 2",
      body: "Second issue",
      author: { id: 1, username: "testuser" },
    });

    await createIssue(TEST_USER, TEST_REPO, {
      title: "Issue 3",
      body: "Third issue",
      author: { id: 1, username: "testuser" },
    });
  });

  afterEach(async () => {
    // Clean up test directory
    if (existsSync(TEST_PATH)) {
      await rm(TEST_PATH, { recursive: true });
    }
  });

  test("addDependency creates bidirectional link", async () => {
    const result = await addDependency(TEST_USER, TEST_REPO, 1, 2);

    expect(result.blocking.number).toBe(1);
    expect(result.blocked.number).toBe(2);
    expect(result.blocking.blocks).toContain(2);
    expect(result.blocked.blocked_by).toContain(1);
  });

  test("addDependency prevents self-dependency", async () => {
    try {
      await addDependency(TEST_USER, TEST_REPO, 1, 1);
      expect(true).toBe(false); // Should not reach here
    } catch (error) {
      expect((error as Error).message).toContain("cannot depend on itself");
    }
  });

  test("addDependency is idempotent", async () => {
    await addDependency(TEST_USER, TEST_REPO, 1, 2);
    const result = await addDependency(TEST_USER, TEST_REPO, 1, 2);

    expect(result.blocking.blocks).toEqual([2]);
    expect(result.blocked.blocked_by).toEqual([1]);
  });

  test("removeDependency removes bidirectional link", async () => {
    await addDependency(TEST_USER, TEST_REPO, 1, 2);
    const result = await removeDependency(TEST_USER, TEST_REPO, 1, 2);

    expect(result.blocking.blocks).toEqual([]);
    expect(result.blocked.blocked_by).toEqual([]);
  });

  test("getBlockingIssues returns correct issues", async () => {
    await addDependency(TEST_USER, TEST_REPO, 1, 2);
    await addDependency(TEST_USER, TEST_REPO, 1, 3);

    const blocking = await getBlockingIssues(TEST_USER, TEST_REPO, 1);

    expect(blocking.length).toBe(2);
    expect(blocking.map((i) => i.number)).toContain(2);
    expect(blocking.map((i) => i.number)).toContain(3);
  });

  test("getBlockedByIssues returns correct issues", async () => {
    await addDependency(TEST_USER, TEST_REPO, 1, 3);
    await addDependency(TEST_USER, TEST_REPO, 2, 3);

    const blockedBy = await getBlockedByIssues(TEST_USER, TEST_REPO, 3);

    expect(blockedBy.length).toBe(2);
    expect(blockedBy.map((i) => i.number)).toContain(1);
    expect(blockedBy.map((i) => i.number)).toContain(2);
  });

  test("canCloseIssue returns true when no open blockers", async () => {
    await addDependency(TEST_USER, TEST_REPO, 1, 2);

    // Close issue 1 (the blocker)
    await updateIssue(TEST_USER, TEST_REPO, 1, { state: "closed" });

    const result = await canCloseIssue(TEST_USER, TEST_REPO, 2);

    expect(result.canClose).toBe(true);
    expect(result.openBlockers).toEqual([]);
  });

  test("canCloseIssue returns false when open blockers exist", async () => {
    await addDependency(TEST_USER, TEST_REPO, 1, 2);

    const result = await canCloseIssue(TEST_USER, TEST_REPO, 2);

    expect(result.canClose).toBe(false);
    expect(result.openBlockers.length).toBe(1);
    expect(result.openBlockers[0].number).toBe(1);
    expect(result.openBlockers[0].state).toBe("open");
  });

  test("multiple dependencies can be managed", async () => {
    // Issue 1 blocks both 2 and 3
    await addDependency(TEST_USER, TEST_REPO, 1, 2);
    await addDependency(TEST_USER, TEST_REPO, 1, 3);

    // Issue 2 also blocks 3
    await addDependency(TEST_USER, TEST_REPO, 2, 3);

    const issue1 = await getIssue(TEST_USER, TEST_REPO, 1);
    const issue2 = await getIssue(TEST_USER, TEST_REPO, 2);
    const issue3 = await getIssue(TEST_USER, TEST_REPO, 3);

    expect(issue1?.blocks).toEqual([2, 3]);
    expect(issue1?.blocked_by).toEqual([]);

    expect(issue2?.blocks).toEqual([3]);
    expect(issue2?.blocked_by).toEqual([1]);

    expect(issue3?.blocks).toEqual([]);
    expect(issue3?.blocked_by.sort()).toEqual([1, 2]);
  });
});
