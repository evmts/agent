import { test, expect, describe } from "bun:test";
import {
  getSessionIdFromRequest,
  createSessionCookie,
  clearSessionCookie,
  hashToken,
  generateTokenPair,
  generateCsrfToken,
  createCsrfCookie,
  getCsrfTokenFromCookie,
  getCsrfTokenFromHeader,
  validateCsrfToken,
  validatePassword,
  validateUsername,
  validateEmail,
  validateTextInput,
} from "../auth-helpers";

describe("Session Helpers", () => {
  describe("getSessionIdFromRequest", () => {
    test("extracts session ID from cookie", () => {
      const request = new Request("https://example.com", {
        headers: { cookie: "session=abc123; other=value" },
      });
      const sessionId = getSessionIdFromRequest(request);
      expect(sessionId).toBe("abc123");
    });

    test("returns null when no session cookie", () => {
      const request = new Request("https://example.com", {
        headers: { cookie: "other=value" },
      });
      const sessionId = getSessionIdFromRequest(request);
      expect(sessionId).toBeNull();
    });

    test("returns null when no cookies", () => {
      const request = new Request("https://example.com");
      const sessionId = getSessionIdFromRequest(request);
      expect(sessionId).toBeNull();
    });

    test("handles multiple cookies correctly", () => {
      const request = new Request("https://example.com", {
        headers: { cookie: "first=value1; session=xyz789; last=value2" },
      });
      const sessionId = getSessionIdFromRequest(request);
      expect(sessionId).toBe("xyz789");
    });
  });

  describe("createSessionCookie", () => {
    test("creates secure cookie in production", () => {
      const originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = "production";

      const cookie = createSessionCookie("session123", 3600);

      expect(cookie).toContain("session=session123");
      expect(cookie).toContain("HttpOnly");
      expect(cookie).toContain("Secure");
      expect(cookie).toContain("SameSite=Strict");
      expect(cookie).toContain("Path=/");
      expect(cookie).toContain("Max-Age=3600");

      process.env.NODE_ENV = originalEnv;
    });

    test("creates non-secure cookie in development", () => {
      const originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = "development";

      const cookie = createSessionCookie("session123", 3600);

      expect(cookie).toContain("session=session123");
      expect(cookie).toContain("HttpOnly");
      expect(cookie).not.toContain("Secure");
      expect(cookie).toContain("SameSite=Strict");

      process.env.NODE_ENV = originalEnv;
    });

    test("uses default max age if not provided", () => {
      const cookie = createSessionCookie("session123");
      // 7 days in seconds = 604800
      expect(cookie).toContain("Max-Age=604800");
    });
  });

  describe("clearSessionCookie", () => {
    test("creates expired cookie to clear session", () => {
      const cookie = clearSessionCookie();

      expect(cookie).toContain("session=");
      expect(cookie).toContain("Max-Age=0");
      expect(cookie).toContain("HttpOnly");
      expect(cookie).toContain("SameSite=Strict");
    });
  });
});

describe("Token Security", () => {
  describe("hashToken", () => {
    test("produces consistent hash for same input", () => {
      const hash1 = hashToken("test-token");
      const hash2 = hashToken("test-token");
      expect(hash1).toBe(hash2);
    });

    test("produces different hashes for different inputs", () => {
      const hash1 = hashToken("token1");
      const hash2 = hashToken("token2");
      expect(hash1).not.toBe(hash2);
    });

    test("produces hex string", () => {
      const hash = hashToken("test");
      expect(hash).toMatch(/^[a-f0-9]+$/);
    });

    test("produces 64 character SHA-256 hash", () => {
      const hash = hashToken("test");
      expect(hash).toHaveLength(64);
    });
  });

  describe("generateTokenPair", () => {
    test("generates token and hash pair", () => {
      const pair = generateTokenPair();
      expect(pair).toHaveProperty("token");
      expect(pair).toHaveProperty("hash");
    });

    test("token is 64 hex characters", () => {
      const pair = generateTokenPair();
      expect(pair.token).toHaveLength(64);
      expect(pair.token).toMatch(/^[a-f0-9]+$/);
    });

    test("hash is SHA-256 of token", () => {
      const pair = generateTokenPair();
      const expectedHash = hashToken(pair.token);
      expect(pair.hash).toBe(expectedHash);
    });

    test("generates unique tokens", () => {
      const pair1 = generateTokenPair();
      const pair2 = generateTokenPair();
      expect(pair1.token).not.toBe(pair2.token);
      expect(pair1.hash).not.toBe(pair2.hash);
    });
  });
});

describe("CSRF Protection", () => {
  describe("generateCsrfToken", () => {
    test("generates 64 character hex token", () => {
      const token = generateCsrfToken();
      expect(token).toHaveLength(64);
      expect(token).toMatch(/^[a-f0-9]+$/);
    });

    test("generates unique tokens", () => {
      const token1 = generateCsrfToken();
      const token2 = generateCsrfToken();
      expect(token1).not.toBe(token2);
    });
  });

  describe("createCsrfCookie", () => {
    test("creates CSRF cookie with token", () => {
      const token = "abc123";
      const cookie = createCsrfCookie(token, 3600);

      expect(cookie).toContain("csrf_token=abc123");
      expect(cookie).toContain("SameSite=Strict");
      expect(cookie).toContain("Path=/");
      expect(cookie).toContain("Max-Age=3600");
      expect(cookie).not.toContain("HttpOnly"); // CSRF cookie must be readable by JS
    });

    test("uses default max age", () => {
      const cookie = createCsrfCookie("token");
      // 24 hours = 86400 seconds
      expect(cookie).toContain("Max-Age=86400");
    });
  });

  describe("getCsrfTokenFromCookie", () => {
    test("extracts CSRF token from cookie", () => {
      const request = new Request("https://example.com", {
        headers: { cookie: "csrf_token=abc123; other=value" },
      });
      const token = getCsrfTokenFromCookie(request);
      expect(token).toBe("abc123");
    });

    test("returns null when no CSRF cookie", () => {
      const request = new Request("https://example.com", {
        headers: { cookie: "other=value" },
      });
      const token = getCsrfTokenFromCookie(request);
      expect(token).toBeNull();
    });
  });

  describe("getCsrfTokenFromHeader", () => {
    test("extracts CSRF token from header", () => {
      const request = new Request("https://example.com", {
        headers: { "x-csrf-token": "abc123" },
      });
      const token = getCsrfTokenFromHeader(request);
      expect(token).toBe("abc123");
    });

    test("returns null when no CSRF header", () => {
      const request = new Request("https://example.com");
      const token = getCsrfTokenFromHeader(request);
      expect(token).toBeNull();
    });
  });

  describe("validateCsrfToken", () => {
    test("validates matching tokens", () => {
      const token = "abc123def456";
      const request = new Request("https://example.com", {
        headers: {
          cookie: `csrf_token=${token}`,
          "x-csrf-token": token,
        },
      });
      const isValid = validateCsrfToken(request);
      expect(isValid).toBe(true);
    });

    test("rejects mismatched tokens", () => {
      const request = new Request("https://example.com", {
        headers: {
          cookie: "csrf_token=abc123",
          "x-csrf-token": "xyz789",
        },
      });
      const isValid = validateCsrfToken(request);
      expect(isValid).toBe(false);
    });

    test("rejects when cookie token missing", () => {
      const request = new Request("https://example.com", {
        headers: {
          "x-csrf-token": "abc123",
        },
      });
      const isValid = validateCsrfToken(request);
      expect(isValid).toBe(false);
    });

    test("rejects when header token missing", () => {
      const request = new Request("https://example.com", {
        headers: {
          cookie: "csrf_token=abc123",
        },
      });
      const isValid = validateCsrfToken(request);
      expect(isValid).toBe(false);
    });

    test("uses timing-safe comparison", () => {
      // This test verifies the function doesn't throw on timing comparison
      const request = new Request("https://example.com", {
        headers: {
          cookie: "csrf_token=short",
          "x-csrf-token": "verylongtoken",
        },
      });
      const isValid = validateCsrfToken(request);
      expect(isValid).toBe(false);
    });

    test("handles different length tokens", () => {
      // Different length tokens should be rejected (timing-safe comparison requirement)
      const request = new Request("https://example.com", {
        headers: {
          cookie: "csrf_token=short",
          "x-csrf-token": "verylongtoken123456789",
        },
      });
      const isValid = validateCsrfToken(request);
      expect(isValid).toBe(false);
    });
  });
});

describe("Password Validation", () => {
  describe("validatePassword", () => {
    test("accepts valid password", () => {
      const result = validatePassword("Test123!@#");
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    test("rejects password shorter than 8 characters", () => {
      const result = validatePassword("Test1!");
      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Password must be at least 8 characters long");
    });

    test("rejects password longer than 128 characters", () => {
      const longPassword = "A1!" + "a".repeat(130);
      const result = validatePassword(longPassword);
      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Password must not exceed 128 characters");
    });

    test("rejects password without uppercase letter", () => {
      const result = validatePassword("test123!@#");
      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Password must contain at least one uppercase letter");
    });

    test("rejects password without lowercase letter", () => {
      const result = validatePassword("TEST123!@#");
      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Password must contain at least one lowercase letter");
    });

    test("rejects password without number", () => {
      const result = validatePassword("TestTest!@#");
      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Password must contain at least one number");
    });

    test("rejects password without special character", () => {
      const result = validatePassword("Test1234");
      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Password must contain at least one special character");
    });

    test("returns all errors for completely invalid password", () => {
      const result = validatePassword("short");
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(1);
    });

    test("accepts all valid special characters", () => {
      const specialChars = "!@#$%^&*()_+-=[]{}";
      const result = validatePassword(`Test123${specialChars}`);
      expect(result.valid).toBe(true);
    });
  });
});

describe("Username Validation", () => {
  describe("validateUsername", () => {
    test("accepts valid username", () => {
      const result = validateUsername("test-user_123");
      expect(result.valid).toBe(true);
      expect(result.error).toBeUndefined();
    });

    test("rejects username shorter than 3 characters", () => {
      const result = validateUsername("ab");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Username must be at least 3 characters");
    });

    test("rejects username longer than 39 characters", () => {
      const result = validateUsername("a".repeat(40));
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Username must not exceed 39 characters");
    });

    test("rejects username starting with hyphen", () => {
      const result = validateUsername("-test");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Username must start and end with alphanumeric characters");
    });

    test("rejects username ending with hyphen", () => {
      const result = validateUsername("test-");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Username must start and end with alphanumeric characters");
    });

    test("rejects username with special characters", () => {
      const result = validateUsername("test@user");
      expect(result.valid).toBe(false);
      // The actual error message depends on which validation fails first
      expect(result.error).toContain("Username");
    });

    test("accepts username with numbers", () => {
      const result = validateUsername("user123");
      expect(result.valid).toBe(true);
    });

    test("accepts username with underscores", () => {
      const result = validateUsername("test_user");
      expect(result.valid).toBe(true);
    });

    test("accepts username with hyphens in middle", () => {
      const result = validateUsername("test-user");
      expect(result.valid).toBe(true);
    });

    test("rejects empty username", () => {
      const result = validateUsername("");
      expect(result.valid).toBe(false);
    });
  });
});

describe("Email Validation", () => {
  describe("validateEmail", () => {
    test("accepts valid email", () => {
      const result = validateEmail("user@example.com");
      expect(result.valid).toBe(true);
      expect(result.error).toBeUndefined();
    });

    test("accepts email with subdomain", () => {
      const result = validateEmail("user@mail.example.com");
      expect(result.valid).toBe(true);
    });

    test("accepts email with plus addressing", () => {
      const result = validateEmail("user+tag@example.com");
      expect(result.valid).toBe(true);
    });

    test("rejects email without @", () => {
      const result = validateEmail("userexample.com");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Invalid email format");
    });

    test("rejects email without domain", () => {
      const result = validateEmail("user@");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Invalid email format");
    });

    test("rejects email without username", () => {
      const result = validateEmail("@example.com");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Invalid email format");
    });

    test("rejects email shorter than 5 characters", () => {
      const result = validateEmail("a@b");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Invalid email address");
    });

    test("rejects email longer than 254 characters", () => {
      const longEmail = "a".repeat(250) + "@example.com";
      const result = validateEmail(longEmail);
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Email address too long");
    });

    test("rejects email with spaces", () => {
      const result = validateEmail("user name@example.com");
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Invalid email format");
    });
  });
});

describe("Text Input Validation", () => {
  describe("validateTextInput", () => {
    test("accepts valid text", () => {
      const result = validateTextInput("Hello world", "Message");
      expect(result.valid).toBe(true);
      expect(result.value).toBe("Hello world");
      expect(result.error).toBeUndefined();
    });

    test("trims whitespace", () => {
      const result = validateTextInput("  Hello world  ", "Message");
      expect(result.valid).toBe(true);
      expect(result.value).toBe("Hello world");
    });

    test("accepts empty string when not required", () => {
      const result = validateTextInput("", "Message", { required: false });
      expect(result.valid).toBe(true);
      expect(result.value).toBe("");
    });

    test("rejects empty string when required", () => {
      const result = validateTextInput("", "Message", { required: true });
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Message is required");
    });

    test("rejects null when required", () => {
      const result = validateTextInput(null, "Message", { required: true });
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Message is required");
    });

    test("rejects undefined when required", () => {
      const result = validateTextInput(undefined, "Message", { required: true });
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Message is required");
    });

    test("accepts null when not required", () => {
      const result = validateTextInput(null, "Message", { required: false });
      expect(result.valid).toBe(true);
      expect(result.value).toBe("");
    });

    test("rejects text exceeding max length", () => {
      const result = validateTextInput("a".repeat(101), "Message", { maxLength: 100 });
      expect(result.valid).toBe(false);
      expect(result.error).toBe("Message must not exceed 100 characters");
    });

    test("uses default max length of 1000", () => {
      const result = validateTextInput("a".repeat(1001), "Message");
      expect(result.valid).toBe(false);
      expect(result.error).toContain("1000");
    });

    test("converts non-string to string", () => {
      const result = validateTextInput(123 as any, "Message");
      expect(result.valid).toBe(true);
      expect(result.value).toBe("123");
    });
  });
});
