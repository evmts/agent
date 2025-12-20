/**
 * Client-side authentication functions for SIWE (Sign In With Ethereum).
 */

import { signInWithEthereum, disconnectWallet } from './porto';

const API_BASE = '/api';

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
  const response = await fetch(`${API_BASE}/auth/siwe/nonce`, {
    credentials: 'include',
  });

  if (!response.ok) {
    throw new Error('Failed to get nonce');
  }

  const data = await response.json();
  return data.nonce;
}

/**
 * Connect wallet and attempt to login.
 * Returns:
 * - { status: 'logged_in', user } if wallet is already registered
 * - { status: 'needs_registration', address, message, signature } if new wallet
 */
export async function connectAndLogin(): Promise<{
  status: 'logged_in' | 'needs_registration';
  user?: SiweUser;
  address?: string;
  message?: string;
  signature?: string;
}> {
  // Get nonce from server
  const nonce = await getNonce();

  // Sign message with Porto (opens wallet dialog)
  const { message, signature, address } = await signInWithEthereum({
    domain: window.location.host,
    uri: window.location.origin,
    nonce,
    statement: 'Sign in to Plue',
  });

  // Try to verify (login existing user)
  const response = await fetch(`${API_BASE}/auth/siwe/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, signature }),
    credentials: 'include',
  });

  if (response.ok) {
    const data = await response.json();
    return { status: 'logged_in', user: data.user };
  }

  if (response.status === 404) {
    // Wallet not registered, need to choose username
    return {
      status: 'needs_registration',
      address,
      message,
      signature,
    };
  }

  const error = await response.json();
  throw new Error(error.error || 'Login failed');
}

/**
 * Register a new user with SIWE.
 * Call this after connectAndLogin returns 'needs_registration'.
 */
export async function registerWithSiwe(
  message: string,
  signature: string,
  data: SiweRegistrationData
): Promise<{ user: SiweUser }> {
  const response = await fetch(`${API_BASE}/auth/siwe/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message,
      signature,
      username: data.username,
      displayName: data.displayName,
    }),
    credentials: 'include',
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Registration failed');
  }

  return response.json();
}

/**
 * Logout and disconnect wallet.
 */
export async function logout() {
  const response = await fetch(`${API_BASE}/auth/logout`, {
    method: 'POST',
    credentials: 'include',
  });

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
