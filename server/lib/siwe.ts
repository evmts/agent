/**
 * SIWE (Sign In With Ethereum) utilities for authentication.
 * Uses viem/siwe for message parsing and verification.
 */

import { generateSiweNonce, parseSiweMessage } from 'viem/siwe';
import { verifyMessage } from 'viem';
import sql from '../db/client';

const NONCE_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes

/**
 * Generate and store a new nonce for SIWE authentication.
 */
export async function createNonce(): Promise<string> {
  const nonce = generateSiweNonce();
  const expiresAt = new Date(Date.now() + NONCE_EXPIRY_MS);

  await sql`
    INSERT INTO siwe_nonces (nonce, expires_at)
    VALUES (${nonce}, ${expiresAt})
  `;

  return nonce;
}

/**
 * Validate that a nonce exists, is not expired, and hasn't been used.
 */
export async function validateNonce(nonce: string): Promise<boolean> {
  const [nonceRecord] = await sql<Array<{
    expires_at: Date;
    used_at: Date | null;
  }>>`
    SELECT expires_at, used_at FROM siwe_nonces
    WHERE nonce = ${nonce}
  `;

  if (!nonceRecord) return false;
  if (nonceRecord.used_at) return false; // Already used
  if (new Date() > nonceRecord.expires_at) return false; // Expired

  return true;
}

/**
 * Mark a nonce as used after successful verification.
 */
export async function markNonceUsed(nonce: string, walletAddress: string): Promise<void> {
  await sql`
    UPDATE siwe_nonces
    SET used_at = NOW(), wallet_address = ${walletAddress.toLowerCase()}
    WHERE nonce = ${nonce}
  `;
}

export interface ParsedSiweMessage {
  address: `0x${string}`;
  chainId: number;
  domain: string;
  nonce: string;
  uri: string;
  version: '1';
  issuedAt?: Date;
  expirationTime?: Date;
  notBefore?: Date;
  requestId?: string;
  resources?: string[];
  statement?: string;
}

/**
 * Verify a SIWE message signature.
 * Returns the verified address or null if invalid.
 */
export async function verifySiweSignature(
  message: string,
  signature: `0x${string}`
): Promise<{ valid: boolean; address: string | null; parsedMessage: ParsedSiweMessage | null; error?: string }> {
  try {
    const parsed = parseSiweMessage(message);

    // Ensure required fields exist
    if (!parsed.address || !parsed.nonce) {
      return { valid: false, address: null, parsedMessage: null, error: 'Invalid SIWE message format' };
    }

    // Validate nonce
    const nonceValid = await validateNonce(parsed.nonce);
    if (!nonceValid) {
      return { valid: false, address: null, parsedMessage: null, error: 'Invalid or expired nonce' };
    }

    // Verify signature using viem
    const valid = await verifyMessage({
      address: parsed.address,
      message,
      signature,
    });

    if (!valid) {
      return { valid: false, address: null, parsedMessage: null, error: 'Invalid signature' };
    }

    // Mark nonce as used
    await markNonceUsed(parsed.nonce, parsed.address);

    // Build the parsed message with proper types
    const parsedMessage: ParsedSiweMessage = {
      address: parsed.address,
      chainId: parsed.chainId ?? 1,
      domain: parsed.domain ?? '',
      nonce: parsed.nonce,
      uri: parsed.uri ?? '',
      version: '1',
      issuedAt: parsed.issuedAt,
      expirationTime: parsed.expirationTime,
      notBefore: parsed.notBefore,
      requestId: parsed.requestId,
      resources: parsed.resources,
      statement: parsed.statement,
    };

    return { valid: true, address: parsed.address, parsedMessage };
  } catch (error) {
    return { valid: false, address: null, parsedMessage: null, error: String(error) };
  }
}

/**
 * Clean up expired and used nonces.
 * Should be called periodically (e.g., hourly).
 */
export async function cleanupExpiredNonces(): Promise<number> {
  const result = await sql`
    DELETE FROM siwe_nonces
    WHERE expires_at <= NOW() OR used_at IS NOT NULL
  `;
  return result.count;
}
