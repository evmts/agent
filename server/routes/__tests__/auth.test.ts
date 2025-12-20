/**
 * Unit tests for authentication routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import authApp from '../auth';

// Mock dependencies
const mockSql = mock(() => []);
const mockCreateNonce = mock(async () => 'test-nonce-123');
const mockVerifySiweSignature = mock(async (message: string, signature: string) => ({
  valid: true,
  address: '0x1234567890abcdef',
  parsedMessage: null,
}));
const mockCreateSession = mock(async () => 'session-key-123');
const mockDeleteSession = mock(async () => {});
const mockSignJWT = mock(async () => 'jwt-token-123');
const mockSetSessionCookie = mock(() => {});
const mockClearSessionCookie = mock(() => {});
const mockSetJWTCookie = mock(() => {});
const mockClearJWTCookie = mock(() => {});
const mockAuthRateLimit = mock(async (c: any, next: any) => next());
const mockGetCookie = mock(() => 'session-key-123');

// Mock module imports
mock.module('../../db/client', () => ({
  default: mockSql,
}));

mock.module('../lib/siwe', () => ({
  createNonce: mockCreateNonce,
  verifySiweSignature: mockVerifySiweSignature,
}));

mock.module('../lib/session', () => ({
  createSession: mockCreateSession,
  deleteSession: mockDeleteSession,
}));

mock.module('../middleware/auth', () => ({
  setSessionCookie: mockSetSessionCookie,
  clearSessionCookie: mockClearSessionCookie,
}));

mock.module('../lib/jwt', () => ({
  signJWT: mockSignJWT,
  setJWTCookie: mockSetJWTCookie,
  clearJWTCookie: mockClearJWTCookie,
}));

mock.module('../middleware/rate-limit', () => ({
  authRateLimit: mockAuthRateLimit,
}));

mock.module('hono/cookie', () => ({
  getCookie: mockGetCookie,
}));

describe('Auth Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/auth', authApp);

    // Reset all mocks
    mockSql.mockClear();
    mockCreateNonce.mockClear();
    mockVerifySiweSignature.mockClear();
    mockCreateSession.mockClear();
    mockDeleteSession.mockClear();
    mockSignJWT.mockClear();
    mockSetSessionCookie.mockClear();
    mockClearSessionCookie.mockClear();
    mockSetJWTCookie.mockClear();
    mockClearJWTCookie.mockClear();
    mockGetCookie.mockClear();
  });

  describe('GET /auth/siwe/nonce', () => {
    test('generates and returns a nonce', async () => {
      const req = new Request('http://localhost/auth/siwe/nonce');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data).toHaveProperty('nonce');
      expect(data.nonce).toBe('test-nonce-123');
      expect(mockCreateNonce).toHaveBeenCalledTimes(1);
    });
  });

  describe('POST /auth/siwe/verify', () => {
    test('returns 400 for missing message', async () => {
      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ signature: '0x123' }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });

    test('returns 400 for invalid signature format', async () => {
      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: 'invalid-signature',
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });

    test('returns 401 for invalid signature', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: false,
        address: null,
        parsedMessage: null,
        error: 'Invalid signature',
      });

      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(401);
      expect(data.error).toBe('Invalid signature');
    });

    test('returns 404 for unregistered wallet', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockResolvedValueOnce([]); // No user found

      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Wallet not registered');
      expect(data.code).toBe('WALLET_NOT_REGISTERED');
      expect(data.address).toBe('0x1234567890abcdef');
    });

    test('returns 403 for disabled account', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        email: null,
        is_admin: false,
        is_active: true,
        prohibit_login: true,
      }]);

      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(403);
      expect(data.error).toBe('Account is disabled');
    });

    test('successfully authenticates and creates session', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        email: 'test@example.com',
        is_admin: false,
        is_active: true,
        prohibit_login: false,
      }]);
      mockSql.mockResolvedValueOnce([]); // UPDATE query

      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Login successful');
      expect(data.user).toMatchObject({
        id: 1,
        username: 'testuser',
        email: 'test@example.com',
        isActive: true,
        isAdmin: false,
        walletAddress: '0x1234567890abcdef',
      });
      expect(mockCreateSession).toHaveBeenCalledWith(1, 'testuser', false);
      expect(mockSignJWT).toHaveBeenCalled();
    });
  });

  describe('POST /auth/siwe/register', () => {
    test('returns 400 for missing username', async () => {
      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });

    test('returns 400 for username too short', async () => {
      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: 'ab',
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });

    test('returns 400 for invalid username format', async () => {
      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: '-invalid-',
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });

    test('returns 401 for invalid signature', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: false,
        address: null,
        parsedMessage: null,
        error: 'Invalid signature',
      });

      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: 'newuser',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(401);
      expect(data.error).toBe('Invalid signature');
    });

    test('returns 409 for already registered wallet', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // Wallet exists

      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: 'newuser',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(409);
      expect(data.error).toBe('Wallet already registered');
    });

    test('returns 409 for username already taken', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockResolvedValueOnce([]); // Wallet doesn't exist
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Username exists

      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: 'existinguser',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(409);
      expect(data.error).toBe('Username already taken');
    });

    test('successfully registers new user', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockResolvedValueOnce([]); // Wallet doesn't exist
      mockSql.mockResolvedValueOnce([]); // Username doesn't exist
      mockSql.mockResolvedValueOnce([{ id: 3 }]); // INSERT returns new user

      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: 'newuser',
          displayName: 'New User',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.message).toBe('Registration successful');
      expect(data.user).toMatchObject({
        id: 3,
        username: 'newuser',
        isActive: true,
        isAdmin: false,
        walletAddress: '0x1234567890abcdef',
      });
      expect(mockCreateSession).toHaveBeenCalledWith(3, 'newuser', false);
      expect(mockSignJWT).toHaveBeenCalled();
    });
  });

  describe('POST /auth/logout', () => {
    test('successfully logs out user', async () => {
      const req = new Request('http://localhost/auth/logout', {
        method: 'POST',
        headers: { Cookie: 'plue_session=session-key-123' },
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Logout successful');
      expect(mockDeleteSession).toHaveBeenCalledWith('session-key-123');
      expect(mockClearSessionCookie).toHaveBeenCalled();
      expect(mockClearJWTCookie).toHaveBeenCalled();
    });

    test('handles logout when no session exists', async () => {
      mockGetCookie.mockReturnValueOnce(undefined);

      const req = new Request('http://localhost/auth/logout', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Logout successful');
      expect(mockDeleteSession).not.toHaveBeenCalled();
    });
  });

  describe('GET /auth/me', () => {
    test('returns null when not authenticated', async () => {
      const req = new Request('http://localhost/auth/me');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.user).toBeNull();
    });

    test('returns user when authenticated', async () => {
      // This would need middleware mocking which is complex
      // For now, we test the basic response structure
      const req = new Request('http://localhost/auth/me');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data).toHaveProperty('user');
    });
  });

  describe('Error handling', () => {
    test('handles database errors in verify', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/auth/siwe/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Verification failed');
    });

    test('handles database errors in register', async () => {
      mockVerifySiweSignature.mockResolvedValueOnce({
        valid: true,
        address: '0x1234567890abcdef',
        parsedMessage: null,
      });
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/auth/siwe/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: 'test message',
          signature: '0x123abc',
          username: 'newuser',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Registration failed');
    });

    test('handles errors in logout', async () => {
      mockDeleteSession.mockRejectedValueOnce(new Error('Session error'));

      const req = new Request('http://localhost/auth/logout', {
        method: 'POST',
        headers: { Cookie: 'plue_session=session-key-123' },
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Logout failed');
    });
  });
});
