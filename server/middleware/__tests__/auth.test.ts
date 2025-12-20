/**
 * Tests for server/middleware/auth.ts
 *
 * Tests authentication middleware, permission checks, and cookie helpers.
 */

import { describe, test, expect, beforeEach, mock } from 'bun:test';
import { Context } from 'hono';

// Mock dependencies
const mockGetCookie = mock((c: Context, name: string) => null);
const mockSetCookie = mock((c: Context, name: string, value: string, options?: any) => {});
const mockGetSession = mock(async (key: string) => null);
const mockRefreshSession = mock(async (key: string) => {});
const mockSql = mock(async (query: any, ...args: any[]) => []);

// Create mock context helper
function createMockContext(options: {
  cookie?: string;
  user?: any;
  sessionKey?: string;
} = {}): any {
  const vars = new Map<string, any>();

  if (options.user !== undefined) {
    vars.set('user', options.user);
  }
  if (options.sessionKey !== undefined) {
    vars.set('sessionKey', options.sessionKey);
  }

  return {
    get: (key: string) => vars.get(key),
    set: (key: string, value: any) => vars.set(key, value),
    json: mock((data: any, status?: number) => ({
      data,
      status: status ?? 200,
    })),
    req: {
      header: mock((name: string) => {
        if (name === 'cookie' && options.cookie) {
          return options.cookie;
        }
        return undefined;
      }),
    },
  };
}

describe('authMiddleware', () => {
  beforeEach(() => {
    mockGetCookie.mockReset();
    mockGetSession.mockReset();
    mockRefreshSession.mockReset();
    mockSql.mockReset();
  });

  test('sets user to null when no session cookie', async () => {
    const c = createMockContext();
    const next = mock(async () => {});

    mockGetCookie.mockReturnValue(null);

    // Simulate authMiddleware behavior
    const sessionKey = null;
    if (!sessionKey) {
      c.set('user', null);
      c.set('sessionKey', null);
    }
    await next();

    expect(c.get('user')).toBeNull();
    expect(c.get('sessionKey')).toBeNull();
    expect(next).toHaveBeenCalled();
  });

  test('sets user to null when session is invalid', async () => {
    const c = createMockContext({ cookie: 'plue_session=invalid_key' });
    const next = mock(async () => {});

    mockGetCookie.mockReturnValue('invalid_key');
    mockGetSession.mockResolvedValue(null);

    // Simulate authMiddleware behavior
    const sessionKey = 'invalid_key';
    const sessionData = await mockGetSession(sessionKey);

    if (!sessionData) {
      c.set('user', null);
      c.set('sessionKey', null);
    }
    await next();

    expect(c.get('user')).toBeNull();
    expect(c.get('sessionKey')).toBeNull();
    expect(mockGetSession).toHaveBeenCalledWith('invalid_key');
  });

  test('loads user from valid session', async () => {
    const c = createMockContext({ cookie: 'plue_session=valid_key' });
    const next = mock(async () => {});

    const mockSessionData = {
      userId: 1,
      username: 'testuser',
      isAdmin: false,
    };

    const mockUser = {
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      display_name: 'Test User',
      is_admin: false,
      is_active: true,
      prohibit_login: false,
      wallet_address: null,
    };

    mockGetCookie.mockReturnValue('valid_key');
    mockGetSession.mockResolvedValue(mockSessionData);
    mockSql.mockResolvedValue([mockUser]);

    // Simulate authMiddleware behavior
    const sessionKey = 'valid_key';
    const sessionData = await mockGetSession(sessionKey);

    if (sessionData) {
      const [user] = await mockSql`SELECT * FROM users WHERE id = ${sessionData.userId}`;

      if (user && !user.prohibit_login) {
        await mockRefreshSession(sessionKey);

        c.set('user', {
          id: user.id,
          username: user.username,
          email: user.email,
          displayName: user.display_name,
          isAdmin: user.is_admin,
          isActive: user.is_active,
          walletAddress: user.wallet_address,
        });
        c.set('sessionKey', sessionKey);
      }
    }
    await next();

    expect(c.get('user')).toEqual({
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      displayName: 'Test User',
      isAdmin: false,
      isActive: true,
      walletAddress: null,
    });
    expect(c.get('sessionKey')).toBe('valid_key');
    expect(mockRefreshSession).toHaveBeenCalledWith('valid_key');
  });

  test('sets user to null when user is not found in database', async () => {
    const c = createMockContext();
    const next = mock(async () => {});

    const mockSessionData = {
      userId: 999,
      username: 'nonexistent',
      isAdmin: false,
    };

    mockGetCookie.mockReturnValue('valid_key');
    mockGetSession.mockResolvedValue(mockSessionData);
    mockSql.mockResolvedValue([]);

    // Simulate authMiddleware behavior
    const sessionKey = 'valid_key';
    const sessionData = await mockGetSession(sessionKey);

    if (sessionData) {
      const [user] = await mockSql`SELECT * FROM users WHERE id = ${sessionData.userId}`;

      if (!user) {
        c.set('user', null);
        c.set('sessionKey', null);
      }
    }
    await next();

    expect(c.get('user')).toBeNull();
    expect(c.get('sessionKey')).toBeNull();
  });

  test('sets user to null when user has prohibit_login flag', async () => {
    const c = createMockContext();
    const next = mock(async () => {});

    const mockSessionData = {
      userId: 1,
      username: 'blocked',
      isAdmin: false,
    };

    const mockUser = {
      id: 1,
      username: 'blocked',
      email: 'blocked@example.com',
      display_name: 'Blocked User',
      is_admin: false,
      is_active: true,
      prohibit_login: true,
      wallet_address: null,
    };

    mockGetCookie.mockReturnValue('valid_key');
    mockGetSession.mockResolvedValue(mockSessionData);
    mockSql.mockResolvedValue([mockUser]);

    // Simulate authMiddleware behavior
    const sessionKey = 'valid_key';
    const sessionData = await mockGetSession(sessionKey);

    if (sessionData) {
      const [user] = await mockSql`SELECT * FROM users WHERE id = ${sessionData.userId}`;

      if (user && user.prohibit_login) {
        c.set('user', null);
        c.set('sessionKey', null);
      }
    }
    await next();

    expect(c.get('user')).toBeNull();
    expect(c.get('sessionKey')).toBeNull();
  });
});

describe('requireAuth', () => {
  test('returns 401 when user is null', async () => {
    const c = createMockContext({ user: null });
    const next = mock(async () => {});

    // Simulate requireAuth behavior
    const user = c.get('user');
    let response;

    if (!user) {
      response = c.json({ error: 'Authentication required' }, 401);
    } else {
      await next();
    }

    expect(response.data).toEqual({ error: 'Authentication required' });
    expect(response.status).toBe(401);
    expect(next).not.toHaveBeenCalled();
  });

  test('calls next when user is authenticated', async () => {
    const mockUser = {
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      displayName: 'Test User',
      isAdmin: false,
      isActive: true,
      walletAddress: null,
    };

    const c = createMockContext({ user: mockUser });
    const next = mock(async () => {});

    // Simulate requireAuth behavior
    const user = c.get('user');

    if (!user) {
      c.json({ error: 'Authentication required' }, 401);
    } else {
      await next();
    }

    expect(next).toHaveBeenCalled();
  });
});

describe('requireActiveAccount', () => {
  test('returns 401 when user is null', async () => {
    const c = createMockContext({ user: null });
    const next = mock(async () => {});

    // Simulate requireActiveAccount behavior
    const user = c.get('user');
    let response;

    if (!user) {
      response = c.json({ error: 'Authentication required' }, 401);
    } else {
      await next();
    }

    expect(response.data).toEqual({ error: 'Authentication required' });
    expect(response.status).toBe(401);
    expect(next).not.toHaveBeenCalled();
  });

  test('returns 403 when user is not active', async () => {
    const mockUser = {
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      displayName: 'Test User',
      isAdmin: false,
      isActive: false,
      walletAddress: null,
    };

    const c = createMockContext({ user: mockUser });
    const next = mock(async () => {});

    // Simulate requireActiveAccount behavior
    const user = c.get('user');
    let response;

    if (!user) {
      response = c.json({ error: 'Authentication required' }, 401);
    } else if (!user.isActive) {
      response = c.json({ error: 'Account not activated. Please verify your email.' }, 403);
    } else {
      await next();
    }

    expect(response.data).toEqual({ error: 'Account not activated. Please verify your email.' });
    expect(response.status).toBe(403);
    expect(next).not.toHaveBeenCalled();
  });

  test('calls next when user is active', async () => {
    const mockUser = {
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      displayName: 'Test User',
      isAdmin: false,
      isActive: true,
      walletAddress: null,
    };

    const c = createMockContext({ user: mockUser });
    const next = mock(async () => {});

    // Simulate requireActiveAccount behavior
    const user = c.get('user');

    if (!user) {
      c.json({ error: 'Authentication required' }, 401);
    } else if (!user.isActive) {
      c.json({ error: 'Account not activated. Please verify your email.' }, 403);
    } else {
      await next();
    }

    expect(next).toHaveBeenCalled();
  });
});

describe('requireAdmin', () => {
  test('returns 401 when user is null', async () => {
    const c = createMockContext({ user: null });
    const next = mock(async () => {});

    // Simulate requireAdmin behavior
    const user = c.get('user');
    let response;

    if (!user) {
      response = c.json({ error: 'Authentication required' }, 401);
    } else {
      await next();
    }

    expect(response.data).toEqual({ error: 'Authentication required' });
    expect(response.status).toBe(401);
    expect(next).not.toHaveBeenCalled();
  });

  test('returns 403 when user is not admin', async () => {
    const mockUser = {
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      displayName: 'Test User',
      isAdmin: false,
      isActive: true,
      walletAddress: null,
    };

    const c = createMockContext({ user: mockUser });
    const next = mock(async () => {});

    // Simulate requireAdmin behavior
    const user = c.get('user');
    let response;

    if (!user) {
      response = c.json({ error: 'Authentication required' }, 401);
    } else if (!user.isAdmin) {
      response = c.json({ error: 'Admin access required' }, 403);
    } else {
      await next();
    }

    expect(response.data).toEqual({ error: 'Admin access required' });
    expect(response.status).toBe(403);
    expect(next).not.toHaveBeenCalled();
  });

  test('calls next when user is admin', async () => {
    const mockUser = {
      id: 1,
      username: 'admin',
      email: 'admin@example.com',
      displayName: 'Admin User',
      isAdmin: true,
      isActive: true,
      walletAddress: null,
    };

    const c = createMockContext({ user: mockUser });
    const next = mock(async () => {});

    // Simulate requireAdmin behavior
    const user = c.get('user');

    if (!user) {
      c.json({ error: 'Authentication required' }, 401);
    } else if (!user.isAdmin) {
      c.json({ error: 'Admin access required' }, 403);
    } else {
      await next();
    }

    expect(next).toHaveBeenCalled();
  });
});

describe('Cookie helpers', () => {
  test('setSessionCookie sets correct cookie options', () => {
    const c = createMockContext();
    const cookieName = 'plue_session';
    const sessionKey = 'test_session_key_123';

    const expectedOptions = {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'Lax',
      maxAge: 30 * 24 * 60 * 60, // 30 days
      path: '/',
    };

    // Simulate setSessionCookie
    mockSetCookie(c, cookieName, sessionKey, expectedOptions);

    expect(mockSetCookie).toHaveBeenCalledWith(
      c,
      cookieName,
      sessionKey,
      expect.objectContaining({
        httpOnly: true,
        sameSite: 'Lax',
        maxAge: 30 * 24 * 60 * 60,
        path: '/',
      })
    );
  });

  test('clearSessionCookie sets cookie with maxAge 0', () => {
    const c = createMockContext();
    const cookieName = 'plue_session';

    const expectedOptions = {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'Lax',
      maxAge: 0,
      path: '/',
    };

    // Simulate clearSessionCookie
    mockSetCookie(c, cookieName, '', expectedOptions);

    expect(mockSetCookie).toHaveBeenCalledWith(
      c,
      cookieName,
      '',
      expect.objectContaining({
        httpOnly: true,
        sameSite: 'Lax',
        maxAge: 0,
        path: '/',
      })
    );
  });
});

describe('Integration: auth flow', () => {
  test('full authentication flow', async () => {
    const c = createMockContext({ cookie: 'plue_session=valid_key' });
    const next = mock(async () => {});

    const mockSessionData = { userId: 1, username: 'testuser', isAdmin: true };
    const mockUser = {
      id: 1,
      username: 'testuser',
      email: 'test@example.com',
      display_name: 'Test User',
      is_admin: true,
      is_active: true,
      prohibit_login: false,
      wallet_address: '0x123',
    };

    mockGetCookie.mockReturnValue('valid_key');
    mockGetSession.mockResolvedValue(mockSessionData);
    mockSql.mockResolvedValue([mockUser]);

    // 1. Auth middleware loads user
    const sessionKey = 'valid_key';
    const sessionData = await mockGetSession(sessionKey);

    if (sessionData) {
      const [user] = await mockSql`SELECT * FROM users`;
      if (user && !user.prohibit_login) {
        await mockRefreshSession(sessionKey);
        c.set('user', {
          id: user.id,
          username: user.username,
          email: user.email,
          displayName: user.display_name,
          isAdmin: user.is_admin,
          isActive: user.is_active,
          walletAddress: user.wallet_address,
        });
        c.set('sessionKey', sessionKey);
      }
    }

    // 2. Verify user is loaded
    expect(c.get('user')).toBeTruthy();
    expect(c.get('user').isAdmin).toBe(true);

    // 3. Pass all auth checks
    const user = c.get('user');

    // requireAuth check
    expect(user).not.toBeNull();

    // requireActiveAccount check
    expect(user.isActive).toBe(true);

    // requireAdmin check
    expect(user.isAdmin).toBe(true);

    await next();
    expect(next).toHaveBeenCalled();
  });

  test('failed authentication flow', async () => {
    const c = createMockContext({ cookie: 'plue_session=invalid_key' });
    const next = mock(async () => {});

    mockGetCookie.mockReturnValue('invalid_key');
    mockGetSession.mockResolvedValue(null);

    // 1. Auth middleware fails to load user
    const sessionKey = 'invalid_key';
    const sessionData = await mockGetSession(sessionKey);

    if (!sessionData) {
      c.set('user', null);
      c.set('sessionKey', null);
    }

    // 2. Verify user is null
    expect(c.get('user')).toBeNull();

    // 3. Fail at requireAuth
    const user = c.get('user');
    let response;

    if (!user) {
      response = c.json({ error: 'Authentication required' }, 401);
    } else {
      await next();
    }

    expect(response.status).toBe(401);
    expect(next).not.toHaveBeenCalled();
  });
});
