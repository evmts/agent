/**
 * SIWE (Sign In With Ethereum) utilities for edge worker
 *
 * Implements EIP-4361 authentication at the edge using the official SIWE library.
 * https://docs.login.xyz/
 */

import { SiweMessage, generateNonce as siweGenerateNonce } from 'siwe';

export { SiweMessage };

/**
 * Generate a cryptographically secure nonce for SIWE
 */
export function generateNonce(): string {
  return siweGenerateNonce();
}

/**
 * Verify a SIWE message and signature
 *
 * @param message - The SIWE message object or string
 * @param signature - The signature from the wallet
 * @returns The verified SIWE message with extracted address
 */
export async function verifySiweMessage(
  message: string | SiweMessage,
  signature: string,
  expectedDomain?: string,
  expectedNonce?: string,
): Promise<{ address: string; message: SiweMessage }> {
  // Parse message if string
  const siweMessage = typeof message === 'string'
    ? new SiweMessage(message)
    : message;

  // Verify the signature
  const result = await siweMessage.verify({
    signature,
    domain: expectedDomain,
    nonce: expectedNonce,
  });

  if (!result.success) {
    throw new Error(result.error?.type || 'Signature verification failed');
  }

  return {
    address: siweMessage.address.toLowerCase(),
    message: siweMessage,
  };
}

/**
 * Create a SIWE message for the client to sign
 */
export function createSiweMessage(params: {
  domain: string;
  address: string;
  uri: string;
  version: string;
  chainId: number;
  nonce: string;
  issuedAt?: string;
  expirationTime?: string;
  statement?: string;
}): SiweMessage {
  return new SiweMessage({
    domain: params.domain,
    address: params.address,
    uri: params.uri,
    version: params.version,
    chainId: params.chainId,
    nonce: params.nonce,
    issuedAt: params.issuedAt || new Date().toISOString(),
    expirationTime: params.expirationTime,
    statement: params.statement,
  });
}
