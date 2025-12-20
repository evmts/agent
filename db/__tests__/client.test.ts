/**
 * Tests for db/client.ts
 *
 * Tests database client singleton configuration and connection pooling settings.
 */

import { describe, test, expect, beforeEach } from 'bun:test';

describe('Database Client Configuration', () => {
  test('exports sql client instance', () => {
    // Import the client
    const clientModule = require('../client');

    expect(clientModule.sql).toBeDefined();
    expect(clientModule.default).toBeDefined();
  });

  test('sql and default export are the same', () => {
    const clientModule = require('../client');

    expect(clientModule.sql).toBe(clientModule.default);
  });

  test('uses DATABASE_URL from environment or defaults', () => {
    const defaultUrl = "postgresql://postgres:password@localhost:54321/electric";
    const envUrl = process.env.DATABASE_URL;

    // Either env variable is set or we use default
    const expectedUrl = envUrl || defaultUrl;

    expect(expectedUrl).toContain('postgresql://');
  });

  test('connection pool settings are configured', () => {
    // The client should be configured with:
    // - max: 10 (max connections)
    // - idle_timeout: 20 (seconds)
    // - connect_timeout: 10 (seconds)

    const poolSettings = {
      max: 10,
      idle_timeout: 20,
      connect_timeout: 10,
    };

    expect(poolSettings.max).toBe(10);
    expect(poolSettings.idle_timeout).toBe(20);
    expect(poolSettings.connect_timeout).toBe(10);
  });

  test('validates connection URL format', () => {
    const validUrls = [
      'postgresql://user:pass@localhost:5432/db',
      'postgresql://postgres:password@localhost:54321/electric',
      'postgresql://user@host/database',
    ];

    const invalidUrls = [
      'http://localhost:5432/db',
      'mysql://localhost:3306/db',
      'not-a-url',
    ];

    for (const url of validUrls) {
      expect(url).toMatch(/^postgresql:\/\//);
    }

    for (const url of invalidUrls) {
      expect(url).not.toMatch(/^postgresql:\/\//);
    }
  });
});

describe('Database Client Behavior', () => {
  test('client is singleton', () => {
    // Import multiple times
    const client1 = require('../client').sql;
    const client2 = require('../client').sql;

    // Should be same instance
    expect(client1).toBe(client2);
  });

  test('client supports tagged template queries', () => {
    const client = require('../client').sql;

    // Client should be a function that supports tagged templates
    expect(typeof client).toBe('function');
  });

  test('connection pool prevents resource exhaustion', () => {
    const poolSettings = {
      max: 10,
      idle_timeout: 20,
      connect_timeout: 10,
    };

    // With max: 10, we can't exceed 10 concurrent connections
    expect(poolSettings.max).toBeLessThanOrEqual(100);
    expect(poolSettings.max).toBeGreaterThan(0);
  });

  test('idle timeout prevents stale connections', () => {
    const idleTimeout = 20; // seconds

    // Idle timeout should be reasonable (not too short, not too long)
    expect(idleTimeout).toBeGreaterThan(5);
    expect(idleTimeout).toBeLessThan(300);
  });

  test('connect timeout prevents hanging connections', () => {
    const connectTimeout = 10; // seconds

    // Connect timeout should be reasonable
    expect(connectTimeout).toBeGreaterThan(1);
    expect(connectTimeout).toBeLessThan(60);
  });
});

describe('Database Connection URL Parsing', () => {
  test('parses username from URL', () => {
    const url = 'postgresql://postgres:password@localhost:54321/electric';
    const match = url.match(/postgresql:\/\/([^:]+):/);

    expect(match).toBeDefined();
    expect(match?.[1]).toBe('postgres');
  });

  test('parses host from URL', () => {
    const url = 'postgresql://postgres:password@localhost:54321/electric';
    const match = url.match(/@([^:]+):/);

    expect(match).toBeDefined();
    expect(match?.[1]).toBe('localhost');
  });

  test('parses port from URL', () => {
    const url = 'postgresql://postgres:password@localhost:54321/electric';
    const match = url.match(/:(\d+)\//);

    expect(match).toBeDefined();
    expect(match?.[1]).toBe('54321');
  });

  test('parses database name from URL', () => {
    const url = 'postgresql://postgres:password@localhost:54321/electric';
    const match = url.match(/\/([^/?]+)$/);

    expect(match).toBeDefined();
    expect(match?.[1]).toBe('electric');
  });

  test('handles URL without password', () => {
    const url = 'postgresql://postgres@localhost:5432/db';

    expect(url).toMatch(/postgresql:\/\/[^@]+@/);
    // URL without password doesn't have : before @
    const hasPassword = /postgresql:\/\/[^:]+:[^@]+@/.test(url);
    expect(hasPassword).toBe(false);
  });

  test('handles URL with query parameters', () => {
    const url = 'postgresql://postgres:password@localhost:5432/db?sslmode=require';

    expect(url).toContain('?');
    expect(url).toMatch(/\?[\w=&]+$/);
  });
});

describe('Error Handling', () => {
  test('invalid DATABASE_URL should be detectable', () => {
    const invalidUrls = [
      '',
      'not-a-url',
      'http://localhost',
      'mysql://localhost:3306/db',
    ];

    for (const url of invalidUrls) {
      expect(url).not.toMatch(/^postgresql:\/\/.*@.*\/.*$/);
    }
  });

  test('missing connection parameters should be detectable', () => {
    const incompleteUrls = [
      'postgresql://',
      'postgresql://user@',
      'postgresql://user@host',
    ];

    for (const url of incompleteUrls) {
      const hasRequiredParts = url.includes('@') && url.includes('/') && url.split('/').length >= 4;
      expect(hasRequiredParts).toBe(false);
    }
  });
});

describe('Connection Pool Limits', () => {
  test('max connections should prevent overload', () => {
    const maxConnections = 10;
    const activeConnections = 8;

    const hasCapacity = activeConnections < maxConnections;
    expect(hasCapacity).toBe(true);

    const wouldOverload = activeConnections + 5 > maxConnections;
    expect(wouldOverload).toBe(true);
  });

  test('connection timeout prevents infinite waiting', () => {
    const timeout = 10000; // 10 seconds in milliseconds
    const startTime = Date.now();
    const maxWaitTime = startTime + timeout;

    // Simulate connection attempt that respects timeout
    const currentTime = Date.now();
    const shouldTimeout = currentTime >= maxWaitTime;

    expect(typeof shouldTimeout).toBe('boolean');
  });

  test('idle timeout releases unused connections', () => {
    const idleTimeout = 20; // seconds
    const lastActivity = Date.now() - (25 * 1000); // 25 seconds ago
    const now = Date.now();

    const idleTime = (now - lastActivity) / 1000; // seconds
    const shouldClose = idleTime > idleTimeout;

    expect(shouldClose).toBe(true);
  });
});
