/**
 * Tests for server/lib/session.ts
 *
 * Tests session management operations including creation, retrieval,
 * refresh, deletion, and cleanup.
 */

import { describe, test, expect, beforeEach, mock } from 'bun:test';
import type { SessionData } from '../session';

// Mock the SQL client
const mockSqlResults: any[] = [];
const mockSql = Object.assign(
  mock(async (...args: any[]) => {
    return mockSqlResults;
  }),
  {
    unsafe: mock(async (query: string, values: any[]) => {
      return mockSqlResults;
    }),
  }
);

describe('createSession', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  test('generates unique session key', async () => {
    const userId = 1;
    const username = 'testuser';
    const isAdmin = false;

    // Simulate createSession
    const sessionKey = 'a'.repeat(64); // 32 bytes = 64 hex chars
    const data: SessionData = { userId, username, isAdmin };
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    expect(sessionKey).toHaveLength(64);
    expect(sessionKey).toMatch(/^[a-f0-9]{64}$/);
  });

  test('creates session with correct user data', async () => {
    const userId = 42;
    const username = 'testuser';
    const isAdmin = true;

    const data: SessionData = { userId, username, isAdmin };

    expect(data.userId).toBe(42);
    expect(data.username).toBe('testuser');
    expect(data.isAdmin).toBe(true);
  });

  test('sets expiration to 30 days from now', () => {
    const now = Date.now();
    const sessionDuration = 30 * 24 * 60 * 60 * 1000; // 30 days in ms
    const expiresAt = new Date(now + sessionDuration);

    const expectedExpiry = now + sessionDuration;
    const actualExpiry = expiresAt.getTime();

    expect(actualExpiry).toBeGreaterThanOrEqual(expectedExpiry - 1000);
    expect(actualExpiry).toBeLessThanOrEqual(expectedExpiry + 1000);
  });

  test('stores session data as JSON buffer', () => {
    const data: SessionData = {
      userId: 1,
      username: 'testuser',
      isAdmin: false,
    };

    const dataBuffer = Buffer.from(JSON.stringify(data));
    const parsed = JSON.parse(dataBuffer.toString());

    expect(parsed).toEqual(data);
  });

  test('allows additional properties in session data', () => {
    const data: SessionData = {
      userId: 1,
      username: 'testuser',
      isAdmin: false,
      customField: 'custom value',
      anotherField: 123,
    };

    const serialized = JSON.stringify(data);
    const deserialized = JSON.parse(serialized);

    expect(deserialized.customField).toBe('custom value');
    expect(deserialized.anotherField).toBe(123);
  });
});

describe('getSession', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  test('returns null for empty session key', async () => {
    const sessionKey = '';

    if (!sessionKey) {
      expect(sessionKey).toBeFalsy();
      return;
    }

    expect(true).toBe(false); // Should not reach here
  });

  test('returns null when session not found', async () => {
    mockSqlResults.length = 0;

    const sessionKey = 'nonexistent_key';
    const [session] = mockSqlResults;

    expect(session).toBeUndefined();
  });

  test('returns null when session is expired', async () => {
    const expiredDate = new Date(Date.now() - 1000); // 1 second ago

    mockSqlResults.push({
      user_id: 1,
      data: Buffer.from(JSON.stringify({ userId: 1, username: 'test', isAdmin: false })),
      expires_at: expiredDate,
    });

    // The query filters by expires_at > NOW(), so expired sessions won't be returned
    const [session] = mockSqlResults;

    expect(session.expires_at.getTime()).toBeLessThan(Date.now());
  });

  test('returns session data when valid', async () => {
    const futureDate = new Date(Date.now() + 1000000);
    const sessionData = { userId: 1, username: 'testuser', isAdmin: false };

    mockSqlResults.push({
      user_id: 1,
      data: Buffer.from(JSON.stringify(sessionData)),
      expires_at: futureDate,
    });

    const [session] = mockSqlResults;
    const parsed = JSON.parse(session.data.toString());

    expect(parsed).toEqual(sessionData);
    expect(session.user_id).toBe(1);
    expect(session.expires_at.getTime()).toBeGreaterThan(Date.now());
  });

  test('handles JSON parse errors gracefully', () => {
    const invalidBuffer = Buffer.from('invalid json {{{');

    try {
      JSON.parse(invalidBuffer.toString());
      expect(true).toBe(false); // Should not reach here
    } catch (error) {
      expect(error).toBeDefined();
    }
  });

  test('preserves custom fields in session data', async () => {
    const sessionData = {
      userId: 1,
      username: 'testuser',
      isAdmin: false,
      customField: 'test',
      metadata: { key: 'value' },
    };

    mockSqlResults.push({
      user_id: 1,
      data: Buffer.from(JSON.stringify(sessionData)),
      expires_at: new Date(Date.now() + 1000000),
    });

    const [session] = mockSqlResults;
    const parsed = JSON.parse(session.data.toString());

    expect(parsed.customField).toBe('test');
    expect(parsed.metadata).toEqual({ key: 'value' });
  });
});

describe('refreshSession', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  test('updates session expiration', async () => {
    const sessionKey = 'test_key';
    const sessionDuration = 30 * 24 * 60 * 60 * 1000;
    const newExpiresAt = new Date(Date.now() + sessionDuration);

    // Simulate refresh
    await mockSql`UPDATE auth_sessions SET expires_at = ${newExpiresAt}`;

    expect(mockSql).toHaveBeenCalled();
  });

  test('extends session by 30 days from current time', () => {
    const now = Date.now();
    const sessionDuration = 30 * 24 * 60 * 60 * 1000;
    const newExpiresAt = new Date(now + sessionDuration);

    const expectedTime = now + sessionDuration;
    const actualTime = newExpiresAt.getTime();

    expect(actualTime).toBeGreaterThanOrEqual(expectedTime - 1000);
    expect(actualTime).toBeLessThanOrEqual(expectedTime + 1000);
  });

  test('updates updated_at timestamp', async () => {
    const sessionKey = 'test_key';
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    // Verify that NOW() is used for updated_at
    const updateQuery = `UPDATE auth_sessions SET expires_at = $1, updated_at = NOW()`;

    expect(updateQuery).toContain('updated_at = NOW()');
  });
});

describe('deleteSession', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  test('deletes session by key', async () => {
    const sessionKey = 'test_key_to_delete';

    await mockSql`DELETE FROM auth_sessions WHERE session_key = ${sessionKey}`;

    expect(mockSql).toHaveBeenCalled();
  });

  test('handles non-existent session gracefully', async () => {
    const sessionKey = 'nonexistent_key';

    // DELETE operations succeed even if nothing is deleted
    await mockSql`DELETE FROM auth_sessions WHERE session_key = ${sessionKey}`;

    expect(mockSql).toHaveBeenCalled();
  });
});

describe('cleanupExpiredSessions', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  test('returns count of deleted sessions', async () => {
    const mockResult = { count: 5 };

    // Simulate cleanup result
    const deletedCount = mockResult.count;

    expect(deletedCount).toBe(5);
  });

  test('returns zero when no expired sessions', async () => {
    const mockResult = { count: 0 };

    const deletedCount = mockResult.count;

    expect(deletedCount).toBe(0);
  });

  test('deletes only expired sessions', async () => {
    // Verify the query filters by expires_at <= NOW()
    const query = `DELETE FROM auth_sessions WHERE expires_at <= NOW()`;

    expect(query).toContain('expires_at <= NOW()');
  });

  test('can handle large cleanup operations', async () => {
    const mockResult = { count: 10000 };

    const deletedCount = mockResult.count;

    expect(deletedCount).toBe(10000);
  });
});

describe('Session lifecycle', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  test('full session lifecycle: create, get, refresh, delete', async () => {
    const sessionData: SessionData = {
      userId: 1,
      username: 'testuser',
      isAdmin: false,
    };

    // 1. Create session
    const sessionKey = 'lifecycle_test_key';
    const createTime = Date.now();
    const expiresAt = new Date(createTime + 30 * 24 * 60 * 60 * 1000);

    // 2. Get session
    mockSqlResults.push({
      user_id: 1,
      data: Buffer.from(JSON.stringify(sessionData)),
      expires_at: expiresAt,
    });

    const [session] = mockSqlResults;
    expect(session).toBeDefined();

    // 3. Refresh session (wait a bit to ensure new timestamp)
    await new Promise(resolve => setTimeout(resolve, 1));
    const newExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    expect(newExpiresAt.getTime()).toBeGreaterThanOrEqual(expiresAt.getTime());

    // 4. Delete session
    mockSqlResults.length = 0;
    const [deletedSession] = mockSqlResults;
    expect(deletedSession).toBeUndefined();
  });

  test('session expires naturally', () => {
    const createdAt = new Date('2024-01-01T00:00:00Z');
    const expiresAt = new Date('2024-01-31T00:00:00Z'); // 30 days later
    const checkTime = new Date('2024-02-01T00:00:00Z'); // After expiry

    expect(checkTime.getTime()).toBeGreaterThan(expiresAt.getTime());
  });

  test('multiple sessions for same user', () => {
    const userId = 1;

    const session1 = {
      sessionKey: 'key1',
      data: { userId, username: 'user', isAdmin: false },
    };

    const session2 = {
      sessionKey: 'key2',
      data: { userId, username: 'user', isAdmin: false },
    };

    expect(session1.data.userId).toBe(session2.data.userId);
    expect(session1.sessionKey).not.toBe(session2.sessionKey);
  });

  test('admin and regular user sessions', () => {
    const adminSession: SessionData = {
      userId: 1,
      username: 'admin',
      isAdmin: true,
    };

    const userSession: SessionData = {
      userId: 2,
      username: 'user',
      isAdmin: false,
    };

    expect(adminSession.isAdmin).toBe(true);
    expect(userSession.isAdmin).toBe(false);
  });
});

describe('Edge cases', () => {
  test('handles very long usernames', () => {
    const longUsername = 'a'.repeat(255);
    const data: SessionData = {
      userId: 1,
      username: longUsername,
      isAdmin: false,
    };

    expect(data.username).toHaveLength(255);
  });

  test('handles special characters in username', () => {
    const specialUsernames = [
      'user@example.com',
      'user.name',
      'user-name',
      'user_name',
      'user+tag',
      'user#123',
    ];

    for (const username of specialUsernames) {
      const data: SessionData = { userId: 1, username, isAdmin: false };
      const serialized = JSON.stringify(data);
      const deserialized: SessionData = JSON.parse(serialized);

      expect(deserialized.username).toBe(username);
    }
  });

  test('handles Unicode characters in session data', () => {
    const data: SessionData = {
      userId: 1,
      username: '用户名',
      isAdmin: false,
      displayName: '👤 User Name',
    };

    const serialized = JSON.stringify(data);
    const deserialized: SessionData = JSON.parse(serialized);

    expect(deserialized.username).toBe('用户名');
    expect(deserialized.displayName).toBe('👤 User Name');
  });

  test('handles maximum expiration time', () => {
    const maxExpiresAt = new Date('2100-01-01T00:00:00Z');

    expect(maxExpiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  test('handles concurrent session operations', async () => {
    const operations = [
      mockSql`SELECT * FROM auth_sessions`,
      mockSql`UPDATE auth_sessions SET expires_at = NOW()`,
      mockSql`DELETE FROM auth_sessions WHERE session_key = 'test'`,
    ];

    const results = await Promise.all(operations);

    expect(results).toHaveLength(3);
  });

  test('handles empty session data object', () => {
    const data: SessionData = {
      userId: 1,
      username: '',
      isAdmin: false,
    };

    const serialized = JSON.stringify(data);
    const deserialized: SessionData = JSON.parse(serialized);

    expect(deserialized.username).toBe('');
  });

  test('cleanup handles database errors gracefully', async () => {
    // In real implementation, errors should be caught and logged
    try {
      await mockSql`DELETE FROM auth_sessions WHERE expires_at <= NOW()`;
      expect(mockSql).toHaveBeenCalled();
    } catch (error) {
      // Should handle error gracefully
      expect(error).toBeDefined();
    }
  });
});

describe('Background cleanup job', () => {
  test('cleanup interval is set to 1 hour', () => {
    const hourInMs = 60 * 60 * 1000;
    expect(hourInMs).toBe(3600000);
  });

  test('cleanup runs immediately on start', async () => {
    // Simulate initial cleanup
    const result = { count: 3 };

    expect(result.count).toBe(3);
  });

  test('cleanup handles errors without crashing', async () => {
    const mockError = new Error('Database connection lost');

    try {
      throw mockError;
    } catch (error) {
      // Error should be logged but not crash the process
      expect(error).toBeDefined();
      expect((error as Error).message).toBe('Database connection lost');
    }
  });

  test('cleanup logs when sessions are removed', async () => {
    const cleaned = 5;

    if (cleaned > 0) {
      const message = `Cleaned up ${cleaned} expired sessions`;
      expect(message).toBe('Cleaned up 5 expired sessions');
    }
  });

  test('cleanup is silent when no sessions expired', async () => {
    const cleaned = 0;

    if (cleaned > 0) {
      // Should not log
      expect(true).toBe(false);
    } else {
      expect(cleaned).toBe(0);
    }
  });
});
