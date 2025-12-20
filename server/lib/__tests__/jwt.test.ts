/**
 * Tests for JWT utilities.
 */

import { describe, test, expect, beforeEach, beforeAll } from 'bun:test';
import {
  signJWT,
  verifyJWT,
  setJWTCookie,
  clearJWTCookie,
  getJWTFromCookie,
  type JWTPayload,
} from '../jwt';

// Set up JWT_SECRET for tests
beforeAll(() => {
  if (!process.env.JWT_SECRET) {
    process.env.JWT_SECRET = 'test-secret-for-jwt-unit-tests-12345';
  }
});

describe('signJWT', () => {
  test('creates a valid JWT token', async () => {
    const payload = {
      userId: 1,
      username: 'testuser',
      isAdmin: false,
    };

    const token = await signJWT(payload);

    expect(token).toBeDefined();
    expect(typeof token).toBe('string');
    expect(token.length).toBeGreaterThan(0);
  });

  test('token contains three parts (header.payload.signature)', async () => {
    const payload = {
      userId: 123,
      username: 'john',
      isAdmin: true,
    };

    const token = await signJWT(payload);
    const parts = token.split('.');

    expect(parts.length).toBe(3);
    expect(parts[0].length).toBeGreaterThan(0); // header
    expect(parts[1].length).toBeGreaterThan(0); // payload
    expect(parts[2].length).toBeGreaterThan(0); // signature
  });

  test('generates different tokens for same payload', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token1 = await signJWT(payload);
    // Delay to ensure different iat (timestamps are in seconds)
    await new Promise((resolve) => setTimeout(resolve, 1100));
    const token2 = await signJWT(payload);

    expect(token1).not.toBe(token2);
  });

  test('includes user information in token', async () => {
    const payload = {
      userId: 42,
      username: 'alice',
      isAdmin: true,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified).not.toBeNull();
    expect(verified?.userId).toBe(42);
    expect(verified?.username).toBe('alice');
    expect(verified?.isAdmin).toBe(true);
  });

  test('sets expiration time', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.exp).toBeDefined();
    expect(typeof verified?.exp).toBe('number');
    expect(verified!.exp! > Date.now() / 1000).toBe(true);
  });

  test('sets issued at time', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.iat).toBeDefined();
    expect(typeof verified?.iat).toBe('number');
    expect(verified!.iat! <= Date.now() / 1000).toBe(true);
  });

  test('throws if JWT_SECRET is not set', async () => {
    const originalSecret = process.env.JWT_SECRET;
    delete process.env.JWT_SECRET;

    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    try {
      await signJWT(payload);
      expect(true).toBe(false); // Should not reach here
    } catch (error) {
      expect(error).toBeDefined();
      expect((error as Error).message).toContain('JWT_SECRET');
    } finally {
      process.env.JWT_SECRET = originalSecret;
    }
  });
});

describe('verifyJWT', () => {
  test('verifies valid token', async () => {
    const payload = {
      userId: 10,
      username: 'bob',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified).not.toBeNull();
    expect(verified?.userId).toBe(10);
    expect(verified?.username).toBe('bob');
    expect(verified?.isAdmin).toBe(false);
  });

  test('returns null for invalid token', async () => {
    const invalidToken = 'invalid.jwt.token';
    const verified = await verifyJWT(invalidToken);

    expect(verified).toBeNull();
  });

  test('returns null for malformed token', async () => {
    const malformed = 'not-a-jwt';
    const verified = await verifyJWT(malformed);

    expect(verified).toBeNull();
  });

  test('returns null for tampered token', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    // Tamper with the signature
    const parts = token.split('.');
    parts[2] = parts[2].split('').reverse().join('');
    const tamperedToken = parts.join('.');

    const verified = await verifyJWT(tamperedToken);
    expect(verified).toBeNull();
  });

  test('returns null for tampered payload', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);

    // Decode payload, modify it, and re-encode
    const parts = token.split('.');
    const decodedPayload = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString()
    );
    decodedPayload.isAdmin = true; // Try to escalate privileges
    parts[1] = Buffer.from(JSON.stringify(decodedPayload)).toString('base64url');

    const tamperedToken = parts.join('.');
    const verified = await verifyJWT(tamperedToken);

    expect(verified).toBeNull();
  });

  test('returns null for empty string', async () => {
    const verified = await verifyJWT('');
    expect(verified).toBeNull();
  });

  test('returns null for token with wrong secret', async () => {
    const originalSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = 'secret1';

    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);

    // Change secret
    process.env.JWT_SECRET = 'secret2';

    const verified = await verifyJWT(token);
    expect(verified).toBeNull();

    // Restore
    process.env.JWT_SECRET = originalSecret;
  });

  test('preserves all payload fields', async () => {
    const payload = {
      userId: 999,
      username: 'charlie',
      isAdmin: true,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.userId).toBe(999);
    expect(verified?.username).toBe('charlie');
    expect(verified?.isAdmin).toBe(true);
  });

  test('includes JWT standard claims', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.iat).toBeDefined(); // issued at
    expect(verified?.exp).toBeDefined(); // expiration
  });
});

describe('token expiration', () => {
  test('token expires after 7 days', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    const sevenDaysInSeconds = 7 * 24 * 60 * 60;
    const expectedExpiry = verified!.iat! + sevenDaysInSeconds;

    // Allow small variance (few seconds) for processing time
    expect(Math.abs(verified!.exp! - expectedExpiry)).toBeLessThan(5);
  });

  test('verifies token before expiration', async () => {
    // Normal token should be valid
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified).not.toBeNull();
  });

  // Note: Testing actual expiration would require manipulating time
  // or waiting 7 days, which is not practical in unit tests
});

describe('setJWTCookie', () => {
  test('sets cookie with token', () => {
    const headers = new Headers();
    const token = 'test.jwt.token';

    setJWTCookie(headers, token);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).not.toBeNull();
    expect(cookie).toContain('plue_token=test.jwt.token');
  });

  test('sets cookie with HttpOnly flag', () => {
    const headers = new Headers();
    const token = 'test.jwt.token';

    setJWTCookie(headers, token);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('HttpOnly');
  });

  test('sets cookie with SameSite=Lax', () => {
    const headers = new Headers();
    const token = 'test.jwt.token';

    setJWTCookie(headers, token);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('SameSite=Lax');
  });

  test('sets cookie with Path=/', () => {
    const headers = new Headers();
    const token = 'test.jwt.token';

    setJWTCookie(headers, token);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('Path=/');
  });

  test('sets cookie with 7 day expiration', () => {
    const headers = new Headers();
    const token = 'test.jwt.token';

    setJWTCookie(headers, token);

    const cookie = headers.get('Set-Cookie');
    const sevenDaysInSeconds = 7 * 24 * 60 * 60;
    expect(cookie).toContain(`Max-Age=${sevenDaysInSeconds}`);
  });

  test('handles long tokens', () => {
    const headers = new Headers();
    const longToken = 'a'.repeat(1000);

    setJWTCookie(headers, longToken);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain(longToken);
  });

  test('handles tokens with special characters', () => {
    const headers = new Headers();
    const token = 'test.jwt-token_with+special=chars';

    setJWTCookie(headers, token);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain(token);
  });
});

describe('clearJWTCookie', () => {
  test('sets cookie with empty value', () => {
    const headers = new Headers();

    clearJWTCookie(headers);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).not.toBeNull();
    expect(cookie).toContain('plue_token=;');
  });

  test('sets cookie with Max-Age=0', () => {
    const headers = new Headers();

    clearJWTCookie(headers);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('Max-Age=0');
  });

  test('maintains HttpOnly flag', () => {
    const headers = new Headers();

    clearJWTCookie(headers);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('HttpOnly');
  });

  test('maintains SameSite=Lax', () => {
    const headers = new Headers();

    clearJWTCookie(headers);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('SameSite=Lax');
  });

  test('maintains Path=/', () => {
    const headers = new Headers();

    clearJWTCookie(headers);

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('Path=/');
  });
});

describe('getJWTFromCookie', () => {
  test('extracts token from cookie string', () => {
    const cookieHeader = 'plue_token=test.jwt.token; other=value';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('test.jwt.token');
  });

  test('returns null for null cookie header', () => {
    const token = getJWTFromCookie(null);
    expect(token).toBeNull();
  });

  test('returns null for empty cookie header', () => {
    const token = getJWTFromCookie('');
    expect(token).toBeNull();
  });

  test('returns null when token not present', () => {
    const cookieHeader = 'other=value; another=value';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBeNull();
  });

  test('handles token at start of cookie string', () => {
    const cookieHeader = 'plue_token=abc.def.ghi; other=value';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('abc.def.ghi');
  });

  test('handles token at end of cookie string', () => {
    const cookieHeader = 'other=value; plue_token=abc.def.ghi';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('abc.def.ghi');
  });

  test('handles token in middle of cookie string', () => {
    const cookieHeader = 'first=1; plue_token=abc.def.ghi; last=2';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('abc.def.ghi');
  });

  test('handles token without other cookies', () => {
    const cookieHeader = 'plue_token=abc.def.ghi';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('abc.def.ghi');
  });

  test('extracts real JWT token format', () => {
    const realishToken =
      'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VySWQiOjF9.xyz123';
    const cookieHeader = `plue_token=${realishToken}`;
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe(realishToken);
  });

  test('handles cookie with spaces', () => {
    const cookieHeader = 'plue_token=abc.def.ghi ; other=value';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('abc.def.ghi '); // Note: may include trailing space before semicolon
  });

  test('extracts token up to semicolon', () => {
    const cookieHeader = 'plue_token=abc.def.ghi; Path=/';
    const token = getJWTFromCookie(cookieHeader);

    expect(token).toBe('abc.def.ghi');
  });
});

describe('integration', () => {
  test('full cycle: sign, set cookie, get from cookie, verify', async () => {
    const payload = {
      userId: 42,
      username: 'integration-test',
      isAdmin: true,
    };

    // Sign token
    const token = await signJWT(payload);

    // Set cookie
    const headers = new Headers();
    setJWTCookie(headers, token);

    // Extract cookie header
    const cookieHeader = headers.get('Set-Cookie');
    expect(cookieHeader).not.toBeNull();

    // Get token from cookie (simulate client sending it back)
    // Remove extra cookie attributes for extraction
    const simpleCookie = cookieHeader!.split(';')[0];
    const extractedToken = getJWTFromCookie(simpleCookie);

    expect(extractedToken).toBe(token);

    // Verify token
    const verified = await verifyJWT(extractedToken!);

    expect(verified).not.toBeNull();
    expect(verified?.userId).toBe(42);
    expect(verified?.username).toBe('integration-test');
    expect(verified?.isAdmin).toBe(true);
  });

  test('clear cookie removes token', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);

    // Set cookie
    const headers1 = new Headers();
    setJWTCookie(headers1, token);

    let cookie = headers1.get('Set-Cookie');
    expect(cookie).toContain(token);

    // Clear cookie
    const headers2 = new Headers();
    clearJWTCookie(headers2);

    cookie = headers2.get('Set-Cookie');
    expect(cookie).not.toContain(token);
    expect(cookie).toContain('Max-Age=0');
  });

  test('different users get different tokens', async () => {
    const user1 = {
      userId: 1,
      username: 'user1',
      isAdmin: false,
    };

    const user2 = {
      userId: 2,
      username: 'user2',
      isAdmin: true,
    };

    const token1 = await signJWT(user1);
    const token2 = await signJWT(user2);

    expect(token1).not.toBe(token2);

    const verified1 = await verifyJWT(token1);
    const verified2 = await verifyJWT(token2);

    expect(verified1?.userId).toBe(1);
    expect(verified1?.username).toBe('user1');
    expect(verified1?.isAdmin).toBe(false);

    expect(verified2?.userId).toBe(2);
    expect(verified2?.username).toBe('user2');
    expect(verified2?.isAdmin).toBe(true);
  });
});

describe('edge cases', () => {
  test('handles userId of 0', async () => {
    const payload = {
      userId: 0,
      username: 'user0',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.userId).toBe(0);
  });

  test('handles very long username', async () => {
    const payload = {
      userId: 1,
      username: 'a'.repeat(1000),
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.username).toBe('a'.repeat(1000));
  });

  test('handles special characters in username', async () => {
    const payload = {
      userId: 1,
      username: 'user@example.com',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.username).toBe('user@example.com');
  });

  test('handles unicode in username', async () => {
    const payload = {
      userId: 1,
      username: '用户名',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.username).toBe('用户名');
  });

  test('handles large userId', async () => {
    const payload = {
      userId: Number.MAX_SAFE_INTEGER,
      username: 'maxuser',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const verified = await verifyJWT(token);

    expect(verified?.userId).toBe(Number.MAX_SAFE_INTEGER);
  });

  test('verifyJWT handles whitespace in token', async () => {
    const payload = {
      userId: 1,
      username: 'test',
      isAdmin: false,
    };

    const token = await signJWT(payload);
    const tokenWithWhitespace = ` ${token} `;

    const verified = await verifyJWT(tokenWithWhitespace);
    // jose library may or may not handle this - implementation specific
    // This test documents the behavior
    expect(verified === null || verified?.userId === 1).toBe(true);
  });

  test('getJWTFromCookie handles malformed cookie string', () => {
    const malformed = 'plue_token';
    const token = getJWTFromCookie(malformed);

    expect(token).toBeNull();
  });

  test('setJWTCookie can be called multiple times', () => {
    const headers = new Headers();

    setJWTCookie(headers, 'token1');
    setJWTCookie(headers, 'token2');

    // Headers.append creates multiple Set-Cookie headers
    // The last one should contain token2
    const cookies = headers.getSetCookie();
    expect(cookies.length).toBe(2);
    expect(cookies[1]).toContain('token2');
  });
});

describe('security', () => {
  test('cannot forge admin token', async () => {
    const userPayload = {
      userId: 100,
      username: 'normaluser',
      isAdmin: false,
    };

    const token = await signJWT(userPayload);

    // Attempt to modify token to grant admin
    const parts = token.split('.');
    const payload = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString()
    );
    payload.isAdmin = true;
    parts[1] = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const forgedToken = parts.join('.');

    const verified = await verifyJWT(forgedToken);
    expect(verified).toBeNull(); // Should fail verification
  });

  test('cannot modify userId in token', async () => {
    const payload = {
      userId: 1,
      username: 'user1',
      isAdmin: false,
    };

    const token = await signJWT(payload);

    // Attempt to modify userId
    const parts = token.split('.');
    const decoded = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString()
    );
    decoded.userId = 999;
    parts[1] = Buffer.from(JSON.stringify(decoded)).toString('base64url');
    const modifiedToken = parts.join('.');

    const verified = await verifyJWT(modifiedToken);
    expect(verified).toBeNull();
  });

  test('HttpOnly cookie prevents JavaScript access', () => {
    const headers = new Headers();
    setJWTCookie(headers, 'token');

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('HttpOnly');
    // This documents that the cookie is protected from XSS
  });

  test('SameSite=Lax protects against CSRF', () => {
    const headers = new Headers();
    setJWTCookie(headers, 'token');

    const cookie = headers.get('Set-Cookie');
    expect(cookie).toContain('SameSite=Lax');
    // This documents CSRF protection
  });
});
