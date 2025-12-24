import { test, expect, describe, beforeEach } from "bun:test";
import {
  cacheStatic,
  cacheWithTags,
  cacheShort,
  noCache,
  CacheTags,
} from "../cache";

// Mock Astro context
interface MockAstroContext {
  response: {
    headers: Map<string, string>;
  };
}

function createMockAstro(): MockAstroContext {
  return {
    response: {
      headers: new Map<string, string>(),
    },
  };
}

describe("Cache Utilities", () => {
  describe("cacheStatic", () => {
    test("sets immutable cache for one year", () => {
      const astro = createMockAstro();
      cacheStatic(astro as any);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toBe("public, max-age=31536000, immutable");
    });

    test("does not set cache tags", () => {
      const astro = createMockAstro();
      cacheStatic(astro as any);

      const cacheTags = astro.response.headers.get("Cache-Tag");
      expect(cacheTags).toBeUndefined();
    });
  });

  describe("cacheWithTags", () => {
    test("sets cache with tags", () => {
      const astro = createMockAstro();
      const tags = ["user:123", "repo:456"];
      cacheWithTags(astro as any, tags);

      const cacheControl = astro.response.headers.get("Cache-Control");
      const cacheTags = astro.response.headers.get("Cache-Tag");

      expect(cacheControl).toBe("public, max-age=31536000");
      expect(cacheTags).toBe("user:123,repo:456");
    });

    test("uses default max age of one year", () => {
      const astro = createMockAstro();
      cacheWithTags(astro as any, ["user:123"]);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toContain("max-age=31536000");
    });

    test("accepts custom max age", () => {
      const astro = createMockAstro();
      cacheWithTags(astro as any, ["user:123"], 3600);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toBe("public, max-age=3600");
    });

    test("handles empty tag array", () => {
      const astro = createMockAstro();
      cacheWithTags(astro as any, []);

      const cacheTags = astro.response.headers.get("Cache-Tag");
      expect(cacheTags).toBe("");
    });

    test("joins multiple tags with commas", () => {
      const astro = createMockAstro();
      const tags = ["tag1", "tag2", "tag3", "tag4"];
      cacheWithTags(astro as any, tags);

      const cacheTags = astro.response.headers.get("Cache-Tag");
      expect(cacheTags).toBe("tag1,tag2,tag3,tag4");
    });
  });

  describe("cacheShort", () => {
    test("sets short cache with stale-while-revalidate", () => {
      const astro = createMockAstro();
      cacheShort(astro as any);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toBe("public, max-age=60, stale-while-revalidate=3600");
    });

    test("uses default max age of 60 seconds", () => {
      const astro = createMockAstro();
      cacheShort(astro as any);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toContain("max-age=60");
    });

    test("uses default stale age of 1 hour", () => {
      const astro = createMockAstro();
      cacheShort(astro as any);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toContain("stale-while-revalidate=3600");
    });

    test("accepts custom max age", () => {
      const astro = createMockAstro();
      cacheShort(astro as any, [], 120);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toContain("max-age=120");
    });

    test("accepts custom stale age", () => {
      const astro = createMockAstro();
      cacheShort(astro as any, [], 60, 7200);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toContain("stale-while-revalidate=7200");
    });

    test("sets cache tags when provided", () => {
      const astro = createMockAstro();
      const tags = ["user:123", "repo:456"];
      cacheShort(astro as any, tags);

      const cacheTags = astro.response.headers.get("Cache-Tag");
      expect(cacheTags).toBe("user:123,repo:456");
    });

    test("does not set cache tags when empty array", () => {
      const astro = createMockAstro();
      cacheShort(astro as any, []);

      const cacheTags = astro.response.headers.get("Cache-Tag");
      expect(cacheTags).toBeUndefined();
    });
  });

  describe("noCache", () => {
    test("disables all caching", () => {
      const astro = createMockAstro();
      noCache(astro as any);

      const cacheControl = astro.response.headers.get("Cache-Control");
      expect(cacheControl).toBe("private, no-store, no-cache, must-revalidate");
    });

    test("does not set cache tags", () => {
      const astro = createMockAstro();
      noCache(astro as any);

      const cacheTags = astro.response.headers.get("Cache-Tag");
      expect(cacheTags).toBeUndefined();
    });
  });
});

describe("CacheTags Helpers", () => {
  describe("user", () => {
    test("generates user tag with number ID", () => {
      const tag = CacheTags.user(123);
      expect(tag).toBe("user:123");
    });

    test("generates user tag with string ID", () => {
      const tag = CacheTags.user("abc");
      expect(tag).toBe("user:abc");
    });
  });

  describe("repo", () => {
    test("generates repo tag with owner and name", () => {
      const tag = CacheTags.repo("owner", "repo-name");
      expect(tag).toBe("repo:owner/repo-name");
    });

    test("handles repo names with special characters", () => {
      const tag = CacheTags.repo("owner", "my-repo_v2");
      expect(tag).toBe("repo:owner/my-repo_v2");
    });
  });

  describe("repoById", () => {
    test("generates repo tag with number ID", () => {
      const tag = CacheTags.repoById(456);
      expect(tag).toBe("repo:456");
    });

    test("generates repo tag with string ID", () => {
      const tag = CacheTags.repoById("xyz");
      expect(tag).toBe("repo:xyz");
    });
  });

  describe("issues", () => {
    test("generates issues collection tag", () => {
      const tag = CacheTags.issues(123);
      expect(tag).toBe("repo:123:issues");
    });

    test("accepts string repo ID", () => {
      const tag = CacheTags.issues("abc");
      expect(tag).toBe("repo:abc:issues");
    });
  });

  describe("issue", () => {
    test("generates specific issue tag", () => {
      const tag = CacheTags.issue(123, 456);
      expect(tag).toBe("issue:123:456");
    });

    test("accepts string repo ID", () => {
      const tag = CacheTags.issue("abc", 1);
      expect(tag).toBe("issue:abc:1");
    });
  });

  describe("pulls", () => {
    test("generates pulls collection tag", () => {
      const tag = CacheTags.pulls(123);
      expect(tag).toBe("repo:123:pulls");
    });
  });

  describe("commits", () => {
    test("generates commits collection tag", () => {
      const tag = CacheTags.commits(123);
      expect(tag).toBe("repo:123:commits");
    });
  });
});

describe("Cache Strategy Scenarios", () => {
  test("static landing page", () => {
    const astro = createMockAstro();
    cacheStatic(astro as any);

    const cacheControl = astro.response.headers.get("Cache-Control");
    expect(cacheControl).toContain("immutable");
    expect(cacheControl).toContain("max-age=31536000");
  });

  test("user profile page with tags", () => {
    const astro = createMockAstro();
    const userId = 123;
    cacheWithTags(astro as any, [CacheTags.user(userId)]);

    const cacheControl = astro.response.headers.get("Cache-Control");
    const cacheTags = astro.response.headers.get("Cache-Tag");

    expect(cacheControl).toBe("public, max-age=31536000");
    expect(cacheTags).toBe("user:123");
  });

  test("repository page with multiple tags", () => {
    const astro = createMockAstro();
    const repoId = 456;
    const owner = "testuser";
    const name = "testrepo";

    cacheWithTags(astro as any, [
      CacheTags.repo(owner, name),
      CacheTags.repoById(repoId),
    ]);

    const cacheTags = astro.response.headers.get("Cache-Tag");
    expect(cacheTags).toBe("repo:testuser/testrepo,repo:456");
  });

  test("issues list with short cache", () => {
    const astro = createMockAstro();
    const repoId = 456;

    cacheShort(astro as any, [CacheTags.issues(repoId)], 60, 3600);

    const cacheControl = astro.response.headers.get("Cache-Control");
    const cacheTags = astro.response.headers.get("Cache-Tag");

    expect(cacheControl).toContain("max-age=60");
    expect(cacheControl).toContain("stale-while-revalidate=3600");
    expect(cacheTags).toBe("repo:456:issues");
  });

  test("dashboard with no cache", () => {
    const astro = createMockAstro();
    noCache(astro as any);

    const cacheControl = astro.response.headers.get("Cache-Control");
    expect(cacheControl).toContain("private");
    expect(cacheControl).toContain("no-store");
    expect(cacheControl).toContain("no-cache");
    expect(cacheControl).toContain("must-revalidate");
  });

  test("issue page with granular tags", () => {
    const astro = createMockAstro();
    const repoId = 456;
    const issueNum = 789;

    cacheWithTags(astro as any, [
      CacheTags.issue(repoId, issueNum),
      CacheTags.repoById(repoId),
    ]);

    const cacheTags = astro.response.headers.get("Cache-Tag");
    expect(cacheTags).toBe("issue:456:789,repo:456");
  });
});

describe("Edge Worker Integration", () => {
  test("cache tags are comma-separated for Cloudflare", () => {
    const astro = createMockAstro();
    const tags = ["tag1", "tag2", "tag3"];
    cacheWithTags(astro as any, tags);

    const cacheTags = astro.response.headers.get("Cache-Tag");
    // Cloudflare expects comma-separated tags
    expect(cacheTags).toBe("tag1,tag2,tag3");
    expect(cacheTags).not.toContain(" ");
  });

  test("max-age is in seconds for HTTP header", () => {
    const astro = createMockAstro();
    const oneHour = 3600;
    cacheWithTags(astro as any, ["test"], oneHour);

    const cacheControl = astro.response.headers.get("Cache-Control");
    expect(cacheControl).toContain(`max-age=${oneHour}`);
  });

  test("public directive allows CDN caching", () => {
    const astro = createMockAstro();
    cacheWithTags(astro as any, ["test"]);

    const cacheControl = astro.response.headers.get("Cache-Control");
    expect(cacheControl).toContain("public");
  });

  test("private directive prevents CDN caching", () => {
    const astro = createMockAstro();
    noCache(astro as any);

    const cacheControl = astro.response.headers.get("Cache-Control");
    expect(cacheControl).toContain("private");
    expect(cacheControl).not.toContain("public");
  });
});
