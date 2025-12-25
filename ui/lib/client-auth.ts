/**
 * Client-side authentication functions for SIWE (Sign In With Ethereum).
 */

import { signInWithEthereum, disconnectWallet } from './porto';

const API_BASE = '/api';

/**
 * Get CSRF token from cookie.
 * The server sets this as a HttpOnly cookie after authentication.
 */
function getCsrfToken(): string | null {
  const cookies = document.cookie.split(';');
  for (const cookie of cookies) {
    const [name, value] = cookie.trim().split('=');
    if (name === 'csrf_token') {
      return value;
    }
  }
  return null;
}

/**
 * Create fetch options with CSRF token header for state-changing requests.
 * Export this for use in other modules that make POST/PUT/PATCH/DELETE requests.
 */
export function withCsrfToken(options: RequestInit = {}): RequestInit {
  const token = getCsrfToken();
  if (token) {
    return {
      ...options,
      headers: {
        ...options.headers,
        'X-CSRF-Token': token,
      },
    };
  }
  return options;
}

export interface SiweUser {
  id: number;
  username: string;
  email: string | null;
  isActive: boolean;
  isAdmin: boolean;
  walletAddress: string;
}

export interface SiweRegistrationData {
  username: string;
  displayName?: string;
}

/**
 * Get a fresh nonce from the server for SIWE.
 */
async function getNonce(): Promise<string> {
  const response = await fetch(`${API_BASE}/auth/nonce`, {
    credentials: 'include',
  });

  if (!response.ok) {
    throw new Error('Failed to get nonce');
  }

  const data = await response.json();
  return data.nonce;
}

/**
 * Connect wallet and sign in.
 * Auto-creates account if wallet is new.
 */
export async function connectAndLogin(): Promise<{ user: SiweUser }> {
  // Get nonce from server
  const nonce = await getNonce();

  // Sign message with Porto (opens wallet dialog)
  const { message, signature } = await signInWithEthereum({
    domain: window.location.host,
    uri: window.location.origin,
    nonce,
    statement: 'Sign in to Plue',
  });

  // Verify signature (auto-creates user if new wallet)
  const response = await fetch(`${API_BASE}/auth/verify`, withCsrfToken({
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, signature }),
    credentials: 'include',
  }));

  if (response.ok) {
    const data = await response.json();
    return { user: data.user };
  }

  const error = await response.json();
  throw new Error(error.error || 'Login failed');
}

/**
 * Register a new user with SIWE.
 * NOTE: Edge worker auto-creates users, so this function is deprecated.
 * Kept for backwards compatibility but should not be used.
 */
export async function registerWithSiwe(
  message: string,
  signature: string,
  data: SiweRegistrationData
): Promise<{ user: SiweUser }> {
  throw new Error('Registration is automatic - users are created on first login');
}

/**
 * Logout and disconnect wallet.
 */
export async function logout() {
  const response = await fetch(`${API_BASE}/auth/logout`, withCsrfToken({
    method: 'POST',
    credentials: 'include',
  }));

  // Disconnect wallet state
  disconnectWallet();

  if (!response.ok) {
    throw new Error('Logout failed');
  }

  return response.json();
}

/**
 * Get current authenticated user.
 */
export async function getCurrentUser(): Promise<SiweUser | null> {
  const response = await fetch(`${API_BASE}/auth/me`, {
    credentials: 'include',
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json();
  return data.user;
}
