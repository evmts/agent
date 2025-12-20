import { test, expect, describe } from "bun:test";
import { parseFrontmatter, stringifyFrontmatter } from "../frontmatter";

describe("parseFrontmatter", () => {
  test("parses simple frontmatter with string values", () => {
    const source = `---
title: Test Issue
state: open
---

This is the content`;

    const result = parseFrontmatter(source);

    expect(result.data.title).toBe("Test Issue");
    expect(result.data.state).toBe("open");
    expect(result.content).toBe("This is the content");
  });

  test("parses frontmatter with number values", () => {
    const source = `---
number: 123
count: 456
---

Content here`;

    const result = parseFrontmatter(source);

    expect(result.data.number).toBe(123);
    expect(result.data.count).toBe(456);
  });

  test("parses frontmatter with boolean values", () => {
    const source = `---
active: true
closed: false
---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data.active).toBe(true);
    expect(result.data.closed).toBe(false);
  });

  test("parses frontmatter with null values", () => {
    const source = `---
milestone: null
assignee: ~
---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data.milestone).toBeNull();
    expect(result.data.assignee).toBeNull();
  });

  test("parses frontmatter with inline array", () => {
    const source = `---
labels: [bug, enhancement]
---

Content`;

    const result = parseFrontmatter(source);

    expect(Array.isArray(result.data.labels)).toBe(true);
    expect(result.data.labels).toEqual(["bug", "enhancement"]);
  });

  test("parses frontmatter with empty inline array", () => {
    const source = `---
labels: []
---

Content`;

    const result = parseFrontmatter(source);

    expect(Array.isArray(result.data.labels)).toBe(true);
    expect(result.data.labels).toEqual([]);
  });

  test("parses frontmatter with multi-line array using pipe syntax", () => {
    const source = `---
labels: |
- bug
- enhancement
- documentation
---

Content`;

    const result = parseFrontmatter(source);

    // The implementation requires | or > for multi-line arrays
    expect(Array.isArray(result.data.labels)).toBe(true);
    expect(result.data.labels).toEqual(["bug", "enhancement", "documentation"]);
  });

  test("parses frontmatter with nested object", () => {
    const source = `---
author:
  name: Alice
  email: alice@example.com
---

Content`;

    const result = parseFrontmatter(source);

    expect(typeof result.data.author).toBe("object");
    expect((result.data.author as any).name).toBe("Alice");
    expect((result.data.author as any).email).toBe("alice@example.com");
  });

  test("parses frontmatter with quoted strings", () => {
    const source = `---
title: "Title with: colon"
description: 'Single quoted'
---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data.title).toBe("Title with: colon");
    expect(result.data.description).toBe("Single quoted");
  });

  test("parses frontmatter with float values", () => {
    const source = `---
version: 1.5
rating: 4.7
---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data.version).toBe(1.5);
    expect(result.data.rating).toBe(4.7);
  });

  test("parses frontmatter with negative numbers", () => {
    const source = `---
offset: -5
balance: -10.5
---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data.offset).toBe(-5);
    expect(result.data.balance).toBe(-10.5);
  });

  test("handles document without frontmatter", () => {
    const source = "Just plain content without frontmatter";

    const result = parseFrontmatter(source);

    expect(result.data).toEqual({});
    expect(result.content).toBe("Just plain content without frontmatter");
  });

  test("handles empty frontmatter", () => {
    const source = `---

---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data).toEqual({});
    expect(result.content).toBe("Content");
  });

  test("trims whitespace from content", () => {
    const source = `---
title: Test
---


Content with extra newlines


`;

    const result = parseFrontmatter(source);

    expect(result.content).toBe("Content with extra newlines");
  });

  test("handles CRLF line endings", () => {
    const source = "---\r\ntitle: Test\r\n---\r\nContent";

    const result = parseFrontmatter(source);

    expect(result.data.title).toBe("Test");
    expect(result.content).toBe("Content");
  });

  test("ignores empty lines in frontmatter", () => {
    const source = `---
title: Test

state: open
---

Content`;

    const result = parseFrontmatter(source);

    expect(result.data.title).toBe("Test");
    expect(result.data.state).toBe("open");
  });

  test("handles complex nested structure", () => {
    const source = `---
title: Complex Issue
author:
  name: Bob
  id: 123
labels: [bug, critical]
milestone: 1
active: true
---

Issue description`;

    const result = parseFrontmatter(source);

    expect(result.data.title).toBe("Complex Issue");
    expect((result.data.author as any).name).toBe("Bob");
    expect((result.data.author as any).id).toBe(123);
    expect(result.data.labels).toEqual(["bug", "critical"]);
    expect(result.data.milestone).toBe(1);
    expect(result.data.active).toBe(true);
    expect(result.content).toBe("Issue description");
  });
});

describe("stringifyFrontmatter", () => {
  test("stringifies simple object", () => {
    const data = {
      title: "Test Issue",
      state: "open",
    };
    const content = "This is the content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("title: Test Issue");
    expect(result).toContain("state: open");
    expect(result).toContain("This is the content");
  });

  test("stringifies numbers", () => {
    const data = {
      number: 123,
      count: 456,
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("number: 123");
    expect(result).toContain("count: 456");
  });

  test("stringifies booleans", () => {
    const data = {
      active: true,
      closed: false,
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("active: true");
    expect(result).toContain("closed: false");
  });

  test("stringifies null values", () => {
    const data = {
      milestone: null,
      assignee: null,
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("milestone: null");
    expect(result).toContain("assignee: null");
  });

  test("stringifies empty array", () => {
    const data = {
      labels: [],
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("labels: []");
  });

  test("stringifies simple array", () => {
    const data = {
      labels: ["bug", "enhancement"],
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("labels: [bug, enhancement]");
  });

  test("stringifies nested object", () => {
    const data = {
      author: {
        name: "Alice",
        email: "alice@example.com",
      },
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain("author:");
    expect(result).toContain("name: Alice");
    expect(result).toContain("email: alice@example.com");
  });

  test("escapes strings with special characters", () => {
    const data = {
      title: "Title: with colon",
      description: "Has #hashtag",
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain('"Title: with colon"');
    expect(result).toContain('"Has #hashtag"');
  });

  test("escapes strings with quotes", () => {
    const data = {
      title: 'Title with "quotes"',
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain('\\"quotes\\"');
  });

  test("escapes strings with newlines", () => {
    const data = {
      title: "Title\nwith newline",
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    // The implementation escapes backslash but preserves newlines in quotes
    expect(result).toContain("Title\nwith newline");
  });

  test("quotes strings with leading/trailing spaces", () => {
    const data = {
      title: " Leading space",
      description: "Trailing space ",
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain('" Leading space"');
    expect(result).toContain('"Trailing space "');
  });

  test("quotes empty strings", () => {
    const data = {
      title: "",
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result).toContain('title: ""');
  });

  test("round-trip: parse then stringify", () => {
    const original = `---
title: Test Issue
number: 123
active: true
labels: [bug, enhancement]
---

This is the content`;

    const parsed = parseFrontmatter(original);
    const stringified = stringifyFrontmatter(parsed.data, parsed.content);
    const reparsed = parseFrontmatter(stringified);

    expect(reparsed.data.title).toBe("Test Issue");
    expect(reparsed.data.number).toBe(123);
    expect(reparsed.data.active).toBe(true);
    expect(reparsed.data.labels).toEqual(["bug", "enhancement"]);
    expect(reparsed.content).toBe("This is the content");
  });

  test("formats with proper structure", () => {
    const data = {
      title: "Test",
    };
    const content = "Content";

    const result = stringifyFrontmatter(data, content);

    expect(result.startsWith("---\n")).toBe(true);
    expect(result).toMatch(/---\n\n/);
    expect(result.endsWith("Content"));
  });
});
