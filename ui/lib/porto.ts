/**
 * Porto SDK client for Sign In With Ethereum (SIWE) authentication.
 * Uses Porto's embedded wallet dialog for a seamless Web3 UX.
 */

import { Porto } from 'porto';
import { createWalletClient, custom } from 'viem';

// Porto instance (singleton)
let portoInstance: ReturnType<typeof Porto.create> | null = null;

/**
 * Get or create the Porto instance.
 */
export function getPorto() {
  if (!portoInstance) {
    portoInstance = Porto.create();
  }
  return portoInstance;
}

/**
 * Get a viem wallet client configured with Porto's provider.
 */
export function getPortoClient() {
  const porto = getPorto();
  return createWalletClient({
    transport: custom(porto.provider),
  });
}

export interface SiweConfig {
  domain: string;
  uri: string;
  nonce: string;
  statement?: string;
  chainId?: number;
}

/**
 * Connect wallet and sign a SIWE message.
 * This opens the Porto dialog for wallet selection and message signing.
 */
export async function signInWithEthereum(config: SiweConfig): Promise<{
  message: string;
  signature: string;
  address: string;
}> {
  const client = getPortoClient();

  // Request wallet connection (shows Porto dialog)
  const [address] = await client.requestAddresses();

  // Get chain ID from connected wallet if not specified
  const chainId = config.chainId || (await client.getChainId());

  // Construct SIWE message (EIP-4361 format)
  const issuedAt = new Date().toISOString();
  const message = `${config.domain} wants you to sign in with your Ethereum account:
${address}

${config.statement || 'Sign in to Plue'}

URI: ${config.uri}
Version: 1
Chain ID: ${chainId}
Nonce: ${config.nonce}
Issued At: ${issuedAt}`;

  // Sign the message
  const signature = await client.signMessage({
    account: address,
    message,
  });

  return { message, signature, address };
}

/**
 * Disconnect the wallet (clears Porto state).
 */
export function disconnectWallet() {
  portoInstance = null;
}
