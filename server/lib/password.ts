import { hash, verify } from '@node-rs/argon2';
import { randomBytes, createHash } from 'crypto';

/**
 * Argon2id configuration (secure defaults)
 * Based on OWASP recommendations
 */
const ARGON2_CONFIG = {
  memoryCost: 65536, // 64 MiB
  timeCost: 3,       // 3 iterations
  parallelism: 4,    // 4 threads
};

/**
 * Generate a random salt (32 bytes, hex-encoded)
 */
export function generateSalt(): string {
  return randomBytes(32).toString('hex');
}

/**
 * Hash a password with argon2id
 */
export async function hashPassword(password: string, salt: string): Promise<string> {
  const saltBytes = Buffer.from(salt, 'hex');

  return hash(password, {
    ...ARGON2_CONFIG,
    salt: saltBytes,
  });
}

/**
 * Verify a password against a hash
 */
export async function verifyPassword(
  password: string,
  passwordHash: string,
  salt: string
): Promise<boolean> {
  try {
    const saltBytes = Buffer.from(salt, 'hex');
    return verify(passwordHash, password, {
      ...ARGON2_CONFIG,
      salt: saltBytes,
    });
  } catch (error) {
    console.error('Password verification error:', error);
    return false;
  }
}

/**
 * Check password complexity requirements
 * Minimum 8 characters, at least one uppercase, lowercase, digit
 */
export function validatePasswordComplexity(password: string): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (password.length < 8) {
    errors.push('Password must be at least 8 characters');
  }

  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter');
  }

  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter');
  }

  if (!/[0-9]/.test(password)) {
    errors.push('Password must contain at least one digit');
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Generate a secure random token (for email verification, password reset)
 */
export function generateToken(): { token: string; tokenHash: string } {
  const token = randomBytes(32).toString('hex');
  const tokenHash = createHash('sha256').update(token).digest('hex');

  return { token, tokenHash };
}