/**
 * SSH Server for Git operations.
 *
 * Handles git clone/push over SSH using the ssh2 library.
 * Based on https://github.com/joshnuss/git-ssh-server
 */

import { Server, utils } from 'ssh2';
import { readFileSync, existsSync, writeFileSync, mkdirSync } from 'fs';
import { generateKeyPairSync } from 'crypto';
import { join, dirname } from 'path';
import { authenticate } from './auth';
import { handleSession } from './session';

const HOST_KEY_PATH = process.env.SSH_HOST_KEY_PATH || join(process.env.HOME || '', '.ssh', 'plue_host_key');

/**
 * Generate an RSA host key if one doesn't exist.
 */
function ensureHostKey(): string {
  if (existsSync(HOST_KEY_PATH)) {
    return readFileSync(HOST_KEY_PATH, 'utf-8');
  }

  console.log(`Generating SSH host key at ${HOST_KEY_PATH}`);

  // Ensure directory exists
  const dir = dirname(HOST_KEY_PATH);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }

  // Generate RSA key pair
  const { privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 4096,
    privateKeyEncoding: {
      type: 'pkcs8',
      format: 'pem',
    },
    publicKeyEncoding: {
      type: 'spki',
      format: 'pem',
    },
  });

  writeFileSync(HOST_KEY_PATH, privateKey, { mode: 0o600 });
  console.log(`SSH host key generated at ${HOST_KEY_PATH}`);

  return privateKey;
}

/**
 * Start the SSH server.
 */
export function startSSHServer(port: number = 2222, address: string = '0.0.0.0'): void {
  const hostKey = ensureHostKey();

  const server = new Server(
    {
      hostKeys: [hostKey],
    },
    (client) => {
      console.log('SSH client connected');

      client
        .on('authentication', (ctx) => {
          authenticate(ctx);
        })
        .on('ready', () => {
          console.log('SSH client authenticated');
          client.on('session', (accept, reject) => {
            handleSession(accept, reject, client);
          });
        })
        .on('end', () => {
          console.log('SSH client disconnected');
        })
        .on('error', (err) => {
          console.error('SSH client error:', err.message);
        });
    }
  );

  server.listen(port, address, () => {
    console.log(`SSH server listening on ${address}:${port}`);
  });
}
