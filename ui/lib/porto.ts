/**
 * Porto SDK client for Sign In With Ethereum (SIWE) authentication.
 * Uses Mode.relay for headless operation (with mock passkeys in tests)
 * or Mode.dialog for the embedded wallet UI in production.
 */

import { Porto, Mode } from 'porto';
import { createWalletClient, custom } from 'viem';

// Porto instance (singleton)
let portoInstance: ReturnType<typeof Porto.create> | null = null;

/**
 * Detect if running in Playwright test environment.
 */
function isPlaywright(): boolean {
  if (typeof window === 'undefined') return false;
  // Playwright injects this, or we can set it via addInitScript
  return !!(window as any).__PLAYWRIGHT__ || !!(window as any).__E2E_TEST__;
}

/**
 * Get or create the Porto instance.
 * Uses Mode.relay with mock passkeys in Playwright tests,
 * Mode.dialog (default) in production.
 */
export function getPorto() {
  if (!portoInstance) {
    if (isPlaywright()) {
      // Headless mode with mock passkey for E2E tests
      portoInstance = Porto.create({
        mode: Mode.relay({ mock: true }),
      });
    } else {
      // Production: use dialog mode (iframe/popup)
      portoInstance = Porto.create();
    }
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
 * In mock mode (E2E tests), creates a test account first.
 */
export async function signInWithEthereum(config: SiweConfig): Promise<{
  message: string;
  signature: string;
  address: string;
}> {
  const porto = getPorto();
  const client = getPortoClient();

  let address: `0x${string}`;

  if (isPlaywright()) {
    // In mock mode, use wallet_connect with createAccount capability
    const result = await porto.provider.request({
      method: 'wallet_connect',
      params: [{
        capabilities: {
          createAccount: { label: 'E2E Test Account' },
        },
      }],
    });
    // Extract address from the result
    address = (result as { accounts: Array<{ address: `0x${string}` }> }).accounts[0].address;
  } else {
    // Production: use dialog mode (shows Porto dialog)
    const [addr] = await client.requestAddresses();
    address = addr;
  }

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
