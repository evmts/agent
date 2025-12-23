/**
 * Authentication helper functions for API routes.
 */

import { getUserBySession as dbGetUserBySession } from '../../db';
import type { AuthUser } from './types';
import { createHash, randomBytes, timingSafeEqual } from 'crypto';

// =============================================================================
// Session helpers
// =============================================================================

export function getSessionIdFromRequest(request: Request): string | null {
  const cookies = request.headers.get('cookie') || '';
  const sessionMatch = cookies.match(/session=([^;]+)/);
  return sessionMatch ? sessionMatch[1] : null;
}

export async function getUserBySession(request: Request): Promise<AuthUser | null> {
  const sessionId = getSessionIdFromRequest(request);
  if (!sessionId) {
    return null;
  }

  return await dbGetUserBySession(sessionId);
}

export function createSessionCookie(sessionId: string, maxAge: number = 7 * 24 * 60 * 60): string {
  const isProduction = process.env.NODE_ENV === 'production';
  const secure = isProduction ? 'Secure; ' : '';
  return `session=${sessionId}; HttpOnly; ${secure}SameSite=Strict; Path=/; Max-Age=${maxAge}`;
}

export function clearSessionCookie(): string {
  const isProduction = process.env.NODE_ENV === 'production';
  const secure = isProduction ? 'Secure; ' : '';
  return `session=; HttpOnly; ${secure}SameSite=Strict; Path=/; Max-Age=0`;
}

// =============================================================================
// Token hashing - tokens should be hashed before storage
// =============================================================================

/**
 * Hash a token using SHA-256 for secure storage.
 * The original token is sent to the user, but only the hash is stored.
 */
export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Generate a secure random token and return both the token and its hash.
 */
export function generateTokenPair(): { token: string; hash: string } {
  const token = randomBytes(32).toString('hex');
  const hash = hashToken(token);
  return { token, hash };
}

// =============================================================================
// CSRF Protection
// =============================================================================

const CSRF_COOKIE_NAME = 'csrf_token';
const CSRF_HEADER_NAME = 'x-csrf-token';
const CSRF_TOKEN_LENGTH = 32;

/**
 * Generate a new CSRF token.
 */
export function generateCsrfToken(): string {
  return randomBytes(CSRF_TOKEN_LENGTH).toString('hex');
}

/**
 * Create a CSRF cookie string.
 */
export function createCsrfCookie(token: string, maxAge: number = 24 * 60 * 60): string {
  const isProduction = process.env.NODE_ENV === 'production';
  const secure = isProduction ? 'Secure; ' : '';
  // SameSite=Strict for CSRF cookie, NOT HttpOnly so JS can read it
  return `${CSRF_COOKIE_NAME}=${token}; ${secure}SameSite=Strict; Path=/; Max-Age=${maxAge}`;
}

/**
 * Get CSRF token from request cookie.
 */
export function getCsrfTokenFromCookie(request: Request): string | null {
  const cookies = request.headers.get('cookie') || '';
  const match = cookies.match(new RegExp(`${CSRF_COOKIE_NAME}=([^;]+)`));
  return match ? match[1] : null;
}

/**
 * Get CSRF token from request header.
 */
export function getCsrfTokenFromHeader(request: Request): string | null {
  return request.headers.get(CSRF_HEADER_NAME);
}

/**
 * Validate CSRF token - compares cookie token with header token.
 * Uses timing-safe comparison to prevent timing attacks.
 */
export function validateCsrfToken(request: Request): boolean {
  const cookieToken = getCsrfTokenFromCookie(request);
  const headerToken = getCsrfTokenFromHeader(request);

  if (!cookieToken || !headerToken) {
    return false;
  }

  if (cookieToken.length !== headerToken.length) {
    return false;
  }

  try {
    return timingSafeEqual(
      Buffer.from(cookieToken, 'utf8'),
      Buffer.from(headerToken, 'utf8')
    );
  } catch {
    return false;
  }
}

/**
 * Create a response with CSRF validation error.
 */
export function csrfErrorResponse(): Response {
  return new Response(JSON.stringify({ error: 'Invalid or missing CSRF token' }), {
    status: 403,
    headers: { 'Content-Type': 'application/json' }
  });
}

// =============================================================================
// Password validation
// =============================================================================

export interface PasswordValidationResult {
  valid: boolean;
  errors: string[];
}

/**
 * Validate password complexity.
 * Requirements:
 * - Minimum 8 characters
 * - At least one uppercase letter
 * - At least one lowercase letter
 * - At least one number
 * - At least one special character
 */
export function validatePassword(password: string): PasswordValidationResult {
  const errors: string[] = [];

  if (password.length < 8) {
    errors.push('Password must be at least 8 characters long');
  }

  if (password.length > 128) {
    errors.push('Password must not exceed 128 characters');
  }

  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter');
  }

  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter');
  }

  if (!/[0-9]/.test(password)) {
    errors.push('Password must contain at least one number');
  }

  if (!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(password)) {
    errors.push('Password must contain at least one special character');
  }

  return {
    valid: errors.length === 0,
    errors
  };
}

// =============================================================================
// Input validation
// =============================================================================

/**
 * Validate username format.
 */
export function validateUsername(username: string): { valid: boolean; error?: string } {
  if (!username || username.length < 3) {
    return { valid: false, error: 'Username must be at least 3 characters' };
  }

  if (username.length > 39) {
    return { valid: false, error: 'Username must not exceed 39 characters' };
  }

  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$/.test(username) && username.length > 2) {
    return { valid: false, error: 'Username must start and end with alphanumeric characters' };
  }

  if (!/^[a-zA-Z0-9_-]+$/.test(username)) {
    return { valid: false, error: 'Username can only contain letters, numbers, underscores, and hyphens' };
  }

  return { valid: true };
}

/**
 * Validate email format.
 */
export function validateEmail(email: string): { valid: boolean; error?: string } {
  if (!email || email.length < 5) {
    return { valid: false, error: 'Invalid email address' };
  }

  if (email.length > 254) {
    return { valid: false, error: 'Email address too long' };
  }

  // Basic email regex - not perfect but catches most issues
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    return { valid: false, error: 'Invalid email format' };
  }

  return { valid: true };
}

/**
 * Sanitize and validate text input.
 */
export function validateTextInput(
  input: string | undefined | null,
  fieldName: string,
  options: { maxLength?: number; required?: boolean } = {}
): { valid: boolean; value: string; error?: string } {
  const { maxLength = 1000, required = false } = options;

  if (input === undefined || input === null || input === '') {
    if (required) {
      return { valid: false, value: '', error: `${fieldName} is required` };
    }
    return { valid: true, value: '' };
  }

  const trimmed = String(input).trim();

  if (trimmed.length > maxLength) {
    return { valid: false, value: trimmed, error: `${fieldName} must not exceed ${maxLength} characters` };
  }

  return { valid: true, value: trimmed };
}