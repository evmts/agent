/**
 * Type declarations for E2E test environment
 * Extends Window interface with test utilities and mock objects
 */

interface Window {
  // Authentication functions (from client-auth.ts)
  connectAndLogin?: () => Promise<any>;
  disconnectWallet?: () => void;

  // Test tracking
  wasDisconnectCalled?: boolean;
  lastSiweParams?: any;
  signMessage?: (message: string) => Promise<{ signature: string }>;

  // Ethereum wallet provider (e.g., MetaMask)
  ethereum?: {
    request: (args: { method: string; params?: any[] }) => Promise<any>;
    on: (event: string, handler: (...args: any[]) => void) => void;
    removeListener: (event: string, handler: (...args: any[]) => void) => void;
    emit?: (event: string, ...args: any[]) => void;
  };

  // SIWE functions (from client-auth.ts or porto.ts)
  signInWithEthereum?: (params: {
    domain: string;
    uri: string;
    nonce: string;
    statement?: string;
  }) => Promise<{ message: string; signature: string }>;
}
