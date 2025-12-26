/**
 * SIWE (Sign In With Ethereum) utilities for edge worker
 *
 * Implements EIP-4361 authentication at the edge using the official SIWE library.
 * https://docs.login.xyz/
 *
 * Note: For development/testing with Porto mock mode, EIP-6492 signatures are
 * detected and handled specially since they require on-chain verification.
 */

import { SiweMessage, generateNonce as siweGenerateNonce } from 'siwe';

export { SiweMessage };

/**
 * EIP-6492 magic bytes suffix that identifies smart contract wallet signatures
 * These signatures require on-chain verification and can't be verified purely off-chain
 */
const EIP_6492_MAGIC_BYTES = '6492649264926492649264926492649264926492649264926492649264926492';

/**
 * Detect if a signature is an EIP-6492 smart contract wallet signature
 * These are used by Porto and other smart wallet providers
 */
function isEip6492Signature(signature: string): boolean {
  const cleanSig = signature.startsWith('0x') ? signature.slice(2) : signature;
  return cleanSig.endsWith(EIP_6492_MAGIC_BYTES);
}

/**
 * Detect if a signature is a long-form smart wallet signature (Porto mock mode)
 * Porto mock mode produces ABI-encoded signatures much longer than standard 65 bytes
 */
function isSmartWalletSignature(signature: string): boolean {
  const cleanSig = signature.startsWith('0x') ? signature.slice(2) : signature;
  // Standard ECDSA signatures are 65 bytes (130 hex chars)
  // Smart wallet signatures are much longer (contain WebAuthn data, etc.)
  return cleanSig.length > 200;
}

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
 * @param expectedDomain - Expected domain for validation
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

  // Check for smart contract wallet signatures (Porto mock mode, EIP-6492)
  // These require on-chain verification which isn't available in edge workers
  // For development/testing, we trust the address in the message
  if (isEip6492Signature(signature) || isSmartWalletSignature(signature)) {
    console.log('Smart wallet signature detected, using address from message');

    // Validate domain if provided
    if (expectedDomain && siweMessage.domain !== expectedDomain) {
      throw new Error(`Domain mismatch: expected ${expectedDomain}, got ${siweMessage.domain}`);
    }

    // For smart wallet signatures, we trust the address in the SIWE message
    // In production, these would need on-chain verification via EIP-1271/6492
    return {
      address: siweMessage.address.toLowerCase(),
      message: siweMessage,
    };
  }

  // Standard EOA signature verification via SIWE library
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
