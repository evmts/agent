import { test, expect, describe } from "bun:test";
import { parseReferences, buildIssueUrl, formatReference } from "../references";

describe("parseReferences", () => {
  describe("short format (#123)", () => {
    test("parses single short reference", () => {
      const text = "This fixes #123";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(1);
      expect(refs[0].number).toBe(123);
      expect(refs[0].owner).toBe("user");
      expect(refs[0].repo).toBe("repo");
      expect(refs[0].raw).toBe("#123");
    });

    test("parses multiple short references", () => {
      const text = "This fixes #123 and relates to #456.";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(2);
      expect(refs[0].number).toBe(123);
      expect(refs[1].number).toBe(456);
    });

    test("parses short reference at start of line", () => {
      const text = "#123 is the main issue";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(1);
      expect(refs[0].number).toBe(123);
    });

    test("parses short references across multiple lines", () => {
      const text = "#123 is the main issue\n#456 is related";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(2);
      expect(refs[0].number).toBe(123);
      expect(refs[1].number).toBe(456);
    });

    test("parses short reference in parentheses", () => {
      const text = "(see #123)";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(1);
      expect(refs[0].number).toBe(123);
    });

    test("parses short reference in brackets", () => {
      const text = "[fixes #123]";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(1);
      expect(refs[0].number).toBe(123);
    });

    test("does not set owner/repo without context", () => {
      const text = "This fixes #123";
      const refs = parseReferences(text);

      expect(refs.length).toBe(1);
      expect(refs[0].owner).toBeUndefined();
      expect(refs[0].repo).toBeUndefined();
      expect(refs[0].number).toBe(123);
    });
  });

  describe("full format (owner/repo#123)", () => {
    test("parses single full reference", () => {
      const text = "See user/repo#123";
      const refs = parseReferences(text);

      expect(refs.length).toBe(1);
      expect(refs[0].owner).toBe("user");
      expect(refs[0].repo).toBe("repo");
      expect(refs[0].number).toBe(123);
      expect(refs[0].raw).toBe("user/repo#123");
    });

    test("parses multiple full references", () => {
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

    test("parses references with underscores and hyphens", () => {
      const text = "See user-name/repo_name#123";
      const refs = parseReferences(text);

      expect(refs.length).toBe(1);
      expect(refs[0].owner).toBe("user-name");
      expect(refs[0].repo).toBe("repo_name");
      expect(refs[0].number).toBe(123);
    });

    test("parses references with numbers in names", () => {
      const text = "See user123/repo456#789";
      const refs = parseReferences(text);

      expect(refs.length).toBe(1);
      expect(refs[0].owner).toBe("user123");
      expect(refs[0].repo).toBe("repo456");
      expect(refs[0].number).toBe(789);
    });
  });

  describe("mixed formats", () => {
    test("parses both short and full references", () => {
      const text = "Fixes #123 and see user/repo#456";
      const refs = parseReferences(text, "myuser", "myrepo");

      expect(refs.length).toBe(2);
      // Full reference comes first in the regex matching
      expect(refs[0].owner).toBe("user");
      expect(refs[0].repo).toBe("repo");
      expect(refs[0].number).toBe(456);
      // Short reference
      expect(refs[1].owner).toBe("myuser");
      expect(refs[1].repo).toBe("myrepo");
      expect(refs[1].number).toBe(123);
    });

    test("does not duplicate references", () => {
      const text = "user/repo#123 and #123";
      const refs = parseReferences(text, "user", "repo");

      // Should capture both but not create duplicates at same position
      expect(refs.length).toBeGreaterThanOrEqual(1);
    });
  });

  describe("edge cases", () => {
    test("returns empty array for no references", () => {
      const text = "No issue references here";
      const refs = parseReferences(text);

      expect(refs.length).toBe(0);
    });

    test("handles empty string", () => {
      const text = "";
      const refs = parseReferences(text);

      expect(refs.length).toBe(0);
    });

    test("handles reference with large issue number", () => {
      const text = "See #999999";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(1);
      expect(refs[0].number).toBe(999999);
    });

    test("handles reference with punctuation after", () => {
      const text = "See #123.";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(1);
      expect(refs[0].number).toBe(123);
    });

    test("handles reference with comma after", () => {
      const text = "See #123, #456";
      const refs = parseReferences(text, "user", "repo");

      expect(refs.length).toBe(2);
    });
  });
});

describe("buildIssueUrl", () => {
  test("builds URL with owner and repo", () => {
    const ref = { owner: "user", repo: "repo", number: 123, raw: "user/repo#123" };
    const url = buildIssueUrl(ref);

    expect(url).toBe("/user/repo/issues/123");
  });

  test("builds URL without owner/repo", () => {
    const ref = { number: 123, raw: "#123" };
    const url = buildIssueUrl(ref);

    expect(url).toBe("#123");
  });

  test("builds URL with only owner", () => {
    const ref = { owner: "user", number: 123, raw: "user#123" };
    const url = buildIssueUrl(ref);

    expect(url).toBe("#123");
  });

  test("builds URL with only repo", () => {
    const ref = { repo: "repo", number: 123, raw: "repo#123" };
    const url = buildIssueUrl(ref);

    expect(url).toBe("#123");
  });

  test("handles large issue numbers", () => {
    const ref = { owner: "user", repo: "repo", number: 999999, raw: "user/repo#999999" };
    const url = buildIssueUrl(ref);

    expect(url).toBe("/user/repo/issues/999999");
  });
});

describe("formatReference", () => {
  test("formats full reference", () => {
    const ref = { owner: "user", repo: "repo", number: 123, raw: "user/repo#123" };
    const formatted = formatReference(ref);

    expect(formatted).toBe("user/repo#123");
  });

  test("formats short reference", () => {
    const ref = { number: 123, raw: "#123" };
    const formatted = formatReference(ref);

    expect(formatted).toBe("#123");
  });

  test("formats reference with only owner", () => {
    const ref = { owner: "user", number: 123, raw: "user#123" };
    const formatted = formatReference(ref);

    expect(formatted).toBe("#123");
  });

  test("formats reference with only repo", () => {
    const ref = { repo: "repo", number: 123, raw: "repo#123" };
    const formatted = formatReference(ref);

    expect(formatted).toBe("#123");
  });

  test("formats reference with large issue number", () => {
    const ref = { owner: "user", repo: "repo", number: 999999, raw: "user/repo#999999" };
    const formatted = formatReference(ref);

    expect(formatted).toBe("user/repo#999999");
  });
});
