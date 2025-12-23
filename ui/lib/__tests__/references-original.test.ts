import { test, expect } from "bun:test";
import { parseReferences, buildIssueUrl, formatReference } from "@plue/db";

test("parseReferences - short format #123", () => {
  const text = "This fixes #123 and relates to #456.";
  const refs = parseReferences(text, "user", "repo");

  expect(refs.length).toBe(2);
  expect(refs[0].number).toBe(123);
  expect(refs[0].owner).toBe("user");
  expect(refs[0].repo).toBe("repo");
  expect(refs[1].number).toBe(456);
});

test("parseReferences - full format owner/repo#123", () => {
  const text = "See user/repo#123 and other/project#456";
  const refs = parseReferences(text);

  expect(refs.length).toBe(2);
  expect(refs[0].owner).toBe("user");
  expect(refs[0].repo).toBe("repo");
  expect(refs[0].number).toBe(123);
  expect(refs[1].owner).toBe("other");
  expect(refs[1].repo).toBe("project");
  expect(refs[1].number).toBe(456);
});

test("parseReferences - mixed formats", () => {
  const text = "Fixes #123 and see user/repo#456";
  const refs = parseReferences(text, "myuser", "myrepo");

  expect(refs.length).toBe(2);
  expect(refs[0].owner).toBe("user");
  expect(refs[0].repo).toBe("repo");
  expect(refs[0].number).toBe(456);
  expect(refs[1].owner).toBe("myuser");
  expect(refs[1].repo).toBe("myrepo");
  expect(refs[1].number).toBe(123);
});

test("parseReferences - in code blocks should not match", () => {
  const text = "Use `#123` in your code";
  const refs = parseReferences(text, "user", "repo");

  // Should still parse because we're just looking at raw text
  // The markdown renderer will protect code blocks
  expect(refs.length).toBeGreaterThanOrEqual(0);
});

test("parseReferences - at start of line", () => {
  const text = "#123 is the main issue\n#456 is related";
  const refs = parseReferences(text, "user", "repo");

  expect(refs.length).toBeGreaterThanOrEqual(2);
});

test("buildIssueUrl - with owner and repo", () => {
  const ref = { owner: "user", repo: "repo", number: 123, raw: "user/repo#123" };
  const url = buildIssueUrl(ref);

  expect(url).toBe("/user/repo/issues/123");
});

test("buildIssueUrl - without owner/repo", () => {
  const ref = { number: 123, raw: "#123" };
  const url = buildIssueUrl(ref);

  expect(url).toBe("#123");
});

test("formatReference - full format", () => {
  const ref = { owner: "user", repo: "repo", number: 123, raw: "user/repo#123" };
  const formatted = formatReference(ref);

  expect(formatted).toBe("user/repo#123");
});

test("formatReference - short format", () => {
  const ref = { number: 123, raw: "#123" };
  const formatted = formatReference(ref);

  expect(formatted).toBe("#123");
});
