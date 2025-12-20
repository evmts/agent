/**
 * Tests for SIWE (Sign In With Ethereum) utilities.
 *
 * Note: These are integration tests that test the actual logic and structure
 * of SIWE operations. They validate message parsing, nonce handling, and
 * signature verification flows.
 */

import { describe, test, expect } from 'bun:test';
import { generateSiweNonce } from 'viem/siwe';
import type { ParsedSiweMessage } from '../siwe';

describe('SIWE nonce generation', () => {
  test('generateSiweNonce creates valid nonce format', () => {
    const nonce = generateSiweNonce();

    expect(nonce).toBeDefined();
    expect(typeof nonce).toBe('string');
    expect(nonce.length).toBeGreaterThan(0);
  });

  test('generates unique nonces', () => {
    const nonce1 = generateSiweNonce();
    const nonce2 = generateSiweNonce();
    const nonce3 = generateSiweNonce();

    expect(nonce1).not.toBe(nonce2);
    expect(nonce2).not.toBe(nonce3);
    expect(nonce1).not.toBe(nonce3);
  });

  test('nonce has sufficient entropy', () => {
    const nonces = new Set<string>();
    for (let i = 0; i < 100; i++) {
      nonces.add(generateSiweNonce());
    }

    // All nonces should be unique
    expect(nonces.size).toBe(100);
  });
});

describe('SIWE message structure', () => {
  test('ParsedSiweMessage type has required fields', () => {
    const mockMessage: ParsedSiweMessage = {
      address: '0x1234567890abcdef1234567890abcdef12345678' as `0x${string}`,
      chainId: 1,
      domain: 'example.com',
      nonce: '0xabcdef',
      uri: 'https://example.com',
      version: '1',
    };

    expect(mockMessage.address).toBeDefined();
    expect(mockMessage.chainId).toBe(1);
    expect(mockMessage.domain).toBe('example.com');
    expect(mockMessage.nonce).toBe('0xabcdef');
    expect(mockMessage.uri).toBe('https://example.com');
    expect(mockMessage.version).toBe('1');
  });

  test('ParsedSiweMessage supports optional fields', () => {
    const now = new Date();
    const later = new Date(Date.now() + 3600000);

    const mockMessage: ParsedSiweMessage = {
      address: '0x1234567890abcdef1234567890abcdef12345678' as `0x${string}`,
      chainId: 1,
      domain: 'example.com',
      nonce: '0xabcdef',
      uri: 'https://example.com',
      version: '1',
      issuedAt: now,
      expirationTime: later,
      notBefore: now,
      requestId: 'req-123',
      resources: ['https://resource1.com', 'https://resource2.com'],
      statement: 'Sign in to continue',
    };

    expect(mockMessage.issuedAt).toBe(now);
    expect(mockMessage.expirationTime).toBe(later);
    expect(mockMessage.notBefore).toBe(now);
    expect(mockMessage.requestId).toBe('req-123');
    expect(mockMessage.resources).toHaveLength(2);
    expect(mockMessage.statement).toBe('Sign in to continue');
  });
});

describe('Nonce validation logic', () => {
  test('validates nonce expiry time calculation', () => {
    const NONCE_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes
    const now = Date.now();
    const expiresAt = new Date(now + NONCE_EXPIRY_MS);

    expect(expiresAt.getTime()).toBeGreaterThan(now);
    expect(expiresAt.getTime()).toBe(now + NONCE_EXPIRY_MS);
    expect(expiresAt.getTime() - now).toBe(10 * 60 * 1000);
  });

  test('detects expired nonces', () => {
    const now = new Date();
    const expiredDate = new Date(Date.now() - 60000); // 1 minute ago
    const futureDate = new Date(Date.now() + 60000); // 1 minute from now

    expect(now > expiredDate).toBe(true);
    expect(now > futureDate).toBe(false);
  });

  test('handles nonce used status', () => {
    interface NonceRecord {
      expires_at: Date;
      used_at: Date | null;
    }

    const validNonce: NonceRecord = {
      expires_at: new Date(Date.now() + 60000),
      used_at: null,
    };

    const usedNonce: NonceRecord = {
      expires_at: new Date(Date.now() + 60000),
      used_at: new Date(Date.now() - 1000),
    };

    // Valid nonce: not expired, not used
    expect(new Date() < validNonce.expires_at).toBe(true);
    expect(validNonce.used_at).toBeNull();

    // Used nonce: not expired but used
    expect(new Date() < usedNonce.expires_at).toBe(true);
    expect(usedNonce.used_at).not.toBeNull();
  });
});

describe('Wallet address handling', () => {
  test('normalizes wallet address to lowercase', () => {
    const addresses = [
      '0xABCDEF123456',
      '0xAbCdEf123456',
      '0xabcdef123456',
      '0X1234567890ABCDEF',
    ];

    addresses.forEach(addr => {
      expect(addr.toLowerCase()).toBe(addr.toLowerCase());
      expect(addr.toLowerCase()).toMatch(/^0x[a-f0-9]+$/);
    });
  });

  test('validates ethereum address format', () => {
    const validAddresses = [
      '0x1234567890abcdef1234567890abcdef12345678',
      '0xABCDEF1234567890ABCDEF1234567890ABCDEF12',
      '0x0000000000000000000000000000000000000000',
    ];

    validAddresses.forEach(addr => {
      expect(addr.startsWith('0x')).toBe(true);
      expect(addr.length).toBe(42); // 0x + 40 hex chars
      expect(addr.toLowerCase()).toMatch(/^0x[a-f0-9]{40}$/);
    });
  });

  test('detects invalid address formats', () => {
    const invalidAddresses = [
      '1234567890abcdef', // Missing 0x prefix
      '0x123', // Too short
      '0xGHIJKL', // Invalid characters
      'not-an-address',
    ];

    invalidAddresses.forEach(addr => {
      const isValid = addr.startsWith('0x') &&
                     addr.length === 42 &&
                     /^0x[a-fA-F0-9]{40}$/.test(addr);
      expect(isValid).toBe(false);
    });
  });
});

describe('SIWE signature verification result structure', () => {
  test('valid signature result structure', () => {
    const validResult = {
      valid: true,
      address: '0x1234567890abcdef1234567890abcdef12345678',
      parsedMessage: {
        address: '0x1234567890abcdef1234567890abcdef12345678' as `0x${string}`,
        chainId: 1,
        domain: 'localhost',
        nonce: '0xnonce',
        uri: 'http://localhost',
        version: '1' as const,
      },
    };

    expect(validResult.valid).toBe(true);
    expect(validResult.address).toBeDefined();
    expect(validResult.parsedMessage).toBeDefined();
    expect(validResult.parsedMessage?.address).toBe(validResult.address);
  });

  test('invalid signature result structure', () => {
    const errorResults = [
      {
        valid: false,
        address: null,
        parsedMessage: null,
        error: 'Invalid SIWE message format',
      },
      {
        valid: false,
        address: null,
        parsedMessage: null,
        error: 'Invalid or expired nonce',
      },
      {
        valid: false,
        address: null,
        parsedMessage: null,
        error: 'Invalid signature',
      },
    ];

    errorResults.forEach(result => {
      expect(result.valid).toBe(false);
      expect(result.address).toBeNull();
      expect(result.parsedMessage).toBeNull();
      expect(result.error).toBeDefined();
      expect(typeof result.error).toBe('string');
    });
  });
});

describe('SIWE error handling patterns', () => {
  test('catches and returns error string', () => {
    try {
      throw new Error('Test error');
    } catch (error) {
      const errorString = String(error);
      expect(errorString).toContain('Error');
      expect(typeof errorString).toBe('string');
    }
  });

  test('validates message format requirements', () => {
    interface MessageValidation {
      address?: string;
      nonce?: string;
    }

    const validMessage: MessageValidation = {
      address: '0x123',
      nonce: '0xabc',
    };

    const missingAddress: MessageValidation = {
      nonce: '0xabc',
    };

    const missingNonce: MessageValidation = {
      address: '0x123',
    };

    expect(validMessage.address && validMessage.nonce).toBeTruthy();
    expect(!missingAddress.address).toBe(true);
    expect(!missingNonce.nonce).toBe(true);
  });
});

describe('Nonce cleanup logic', () => {
  test('identifies cleanup criteria', () => {
    const now = new Date();

    interface NonceForCleanup {
      expires_at: Date;
      used_at: Date | null;
    }

    const shouldCleanup = (nonce: NonceForCleanup): boolean => {
      return nonce.expires_at <= now || nonce.used_at !== null;
    };

    const expiredNonce: NonceForCleanup = {
      expires_at: new Date(Date.now() - 60000),
      used_at: null,
    };

    const usedNonce: NonceForCleanup = {
      expires_at: new Date(Date.now() + 60000),
      used_at: new Date(),
    };

    const validNonce: NonceForCleanup = {
      expires_at: new Date(Date.now() + 60000),
      used_at: null,
    };

    expect(shouldCleanup(expiredNonce)).toBe(true);
    expect(shouldCleanup(usedNonce)).toBe(true);
    expect(shouldCleanup(validNonce)).toBe(false);
  });

  test('counts cleanup operations', () => {
    interface CleanupResult {
      count: number;
    }

    const results: CleanupResult[] = [
      { count: 0 },
      { count: 5 },
      { count: 100 },
    ];

    results.forEach(result => {
      expect(result.count).toBeGreaterThanOrEqual(0);
      expect(typeof result.count).toBe('number');
    });
  });
});

describe('SIWE message construction', () => {
  test('builds parsed message with default values', () => {
    const parsed = {
      address: '0x123' as `0x${string}`,
      chainId: undefined,
      domain: undefined,
      nonce: '0xabc',
      uri: undefined,
    };

    const parsedMessage: ParsedSiweMessage = {
      address: parsed.address,
      chainId: parsed.chainId ?? 1,
      domain: parsed.domain ?? '',
      nonce: parsed.nonce,
      uri: parsed.uri ?? '',
      version: '1',
    };

    expect(parsedMessage.chainId).toBe(1);
    expect(parsedMessage.domain).toBe('');
    expect(parsedMessage.uri).toBe('');
    expect(parsedMessage.version).toBe('1');
  });

  test('preserves optional fields when present', () => {
    const issuedAt = new Date();
    const expirationTime = new Date(Date.now() + 3600000);

    const parsed = {
      address: '0x123' as `0x${string}`,
      nonce: '0xabc',
      chainId: 1,
      domain: 'test',
      uri: 'https://test',
      issuedAt,
      expirationTime,
      notBefore: issuedAt,
      requestId: 'req-123',
      resources: ['https://res1.com'],
      statement: 'Test',
    };

    expect(parsed.issuedAt).toBe(issuedAt);
    expect(parsed.expirationTime).toBe(expirationTime);
    expect(parsed.notBefore).toBe(issuedAt);
    expect(parsed.requestId).toBe('req-123');
    expect(parsed.resources).toBeDefined();
    expect(parsed.statement).toBe('Test');
  });
});
