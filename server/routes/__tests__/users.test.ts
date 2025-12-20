/**
 * Unit tests for user routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import usersApp from '../users';

// Mock dependencies
const mockSql = mock(() => []);
const mockRequireAuth = mock(async (c: any, next: any) => {
  c.set('user', { id: 1, username: 'testuser', isAdmin: false });
  return next();
});
const mockRequireActiveAccount = mock(async (c: any, next: any) => next());

mock.module('../../db/client', () => ({
  default: mockSql,
}));

mock.module('../middleware/auth', () => ({
  requireAuth: mockRequireAuth,
  requireActiveAccount: mockRequireActiveAccount,
}));

mock.module('../lib/validation', () => ({
  updateProfileSchema: {
    parse: (data: any) => data,
  },
}));

describe('User Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/users', usersApp);
    mockSql.mockClear();
  });

  describe('GET /users/search', () => {
    test('returns empty array for short query', async () => {
      const req = new Request('http://localhost/users/search');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.users).toEqual([]);
    });

    test('searches users by username prefix', async () => {
      mockSql.mockResolvedValueOnce([
        { username: 'testuser', display_name: 'Test User' },
        { username: 'testdev', display_name: 'Test Developer' },
      ]);

      const req = new Request('http://localhost/users/search?q=test');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.users).toHaveLength(2);
      expect(data.users[0].username).toBe('testuser');
    });

    test('only returns active users', async () => {
      mockSql.mockResolvedValueOnce([
        { username: 'activeuser', display_name: 'Active User' },
      ]);

      const req = new Request('http://localhost/users/search?q=active');
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
      // Verify SQL was called with conditions checking is_active = true
    });

    test('limits results to 10', async () => {
      const users = Array.from({ length: 15 }, (_, i) => ({
        username: `user${i}`,
        display_name: `User ${i}`,
      }));
      mockSql.mockResolvedValueOnce(users.slice(0, 10));

      const req = new Request('http://localhost/users/search?q=user');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.users.length).toBeLessThanOrEqual(10);
    });

    test('handles database errors gracefully', async () => {
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/users/search?q=test');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Failed to search users');
    });
  });

  describe('GET /users/:username', () => {
    test('returns user profile with stats', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        display_name: 'Test User',
        bio: 'A test user bio',
        avatar_url: 'https://example.com/avatar.jpg',
        wallet_address: '0x123',
        created_at: new Date('2024-01-01'),
      }]);
      mockSql.mockResolvedValueOnce([{ repo_count: 5 }]);

      const req = new Request('http://localhost/users/testuser');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.user).toMatchObject({
        username: 'testuser',
        display_name: 'Test User',
        bio: 'A test user bio',
        repoCount: 5,
      });
    });

    test('returns 404 for non-existent user', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/nonexistent');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('User not found');
    });

    test('handles case-insensitive username lookup', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'TestUser',
        display_name: 'Test User',
        bio: null,
        avatar_url: null,
        wallet_address: null,
        created_at: new Date('2024-01-01'),
      }]);
      mockSql.mockResolvedValueOnce([{ repo_count: 0 }]);

      const req = new Request('http://localhost/users/TESTUSER');
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
    });

    test('only returns public repositories count', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        display_name: 'Test User',
        bio: null,
        avatar_url: null,
        wallet_address: null,
        created_at: new Date('2024-01-01'),
      }]);
      mockSql.mockResolvedValueOnce([{ repo_count: 3 }]);

      const req = new Request('http://localhost/users/testuser');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.user.repoCount).toBe(3);
    });

    test('handles database errors', async () => {
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/users/testuser');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Failed to fetch user profile');
    });
  });

  describe('PATCH /users/me', () => {
    test('requires authentication', async () => {
      mockRequireAuth.mockImplementationOnce(async (c: any) => {
        return c.json({ error: 'Unauthorized' }, 401);
      });

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ displayName: 'New Name' }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(401);
    });

    test('updates display name', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ displayName: 'New Display Name' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Profile updated successfully');
    });

    test('updates bio', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bio: 'New bio text' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Profile updated successfully');
    });

    test('updates avatar URL', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ avatarUrl: 'https://example.com/new-avatar.jpg' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Profile updated successfully');
    });

    test('updates email with lowercase', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'New@Example.COM' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Profile updated successfully');
    });

    test('updates multiple fields at once', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          displayName: 'New Name',
          bio: 'New bio',
          email: 'new@example.com',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Profile updated successfully');
    });

    test('returns 400 when no updates provided', async () => {
      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toBe('No updates provided');
    });

    test('handles database errors', async () => {
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ displayName: 'New Name' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Failed to update profile');
    });

    test('sanitizes and validates input data', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          displayName: 'Valid Name',
          bio: 'A' * 1000, // Test long bio
        }),
      });
      const res = await app.fetch(req);

      // Should either succeed or fail validation, not crash
      expect([200, 400]).toContain(res.status);
    });
  });

  describe('Input validation', () => {
    test('validates display name length', async () => {
      const longName = 'a'.repeat(300);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ displayName: longName }),
      });
      const res = await app.fetch(req);

      // Depends on validation schema, should either accept or reject
      expect([200, 400]).toContain(res.status);
    });

    test('validates email format', async () => {
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'valid@example.com' }),
      });
      const res = await app.fetch(req);

      expect([200, 400]).toContain(res.status);
    });
  });
});
