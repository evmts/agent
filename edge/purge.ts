/**
 * Cache purge utilities for Cloudflare.
 *
 * Usage:
 * - On deploy: purgeEverything()
 * - On data change: purgeByTags(['user:123', 'repo:456'])
 *
 * Environment variables required:
 * - CF_ZONE_ID: Cloudflare zone ID
 * - CF_API_TOKEN: Cloudflare API token with cache purge permissions
 */

const CF_API_BASE = 'https://api.cloudflare.com/client/v4';

interface PurgeResult {
  success: boolean;
  errors?: string[];
}

/**
 * Purge entire cache. Use on deploy.
 */
export async function purgeEverything(
  zoneId: string,
  apiToken: string
): Promise<PurgeResult> {
  const response = await fetch(`${CF_API_BASE}/zones/${zoneId}/purge_cache`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ purge_everything: true }),
  });

  const result = await response.json() as { success: boolean; errors?: { message: string }[] };
  return {
    success: result.success,
    errors: result.errors?.map(e => e.message),
  };
}

/**
 * Purge cache by tags. Use when specific data changes.
 */
export async function purgeByTags(
  zoneId: string,
  apiToken: string,
  tags: string[]
): Promise<PurgeResult> {
  const response = await fetch(`${CF_API_BASE}/zones/${zoneId}/purge_cache`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ tags }),
  });

  const result = await response.json() as { success: boolean; errors?: { message: string }[] };
  return {
    success: result.success,
    errors: result.errors?.map(e => e.message),
  };
}

/**
 * Purge cache by URL prefixes.
 */
export async function purgeByPrefixes(
  zoneId: string,
  apiToken: string,
  prefixes: string[]
): Promise<PurgeResult> {
  const response = await fetch(`${CF_API_BASE}/zones/${zoneId}/purge_cache`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ prefixes }),
  });

  const result = await response.json() as { success: boolean; errors?: { message: string }[] };
  return {
    success: result.success,
    errors: result.errors?.map(e => e.message),
  };
}

// CLI usage
if (typeof process !== 'undefined' && process.argv[1]?.endsWith('purge.ts')) {
  const command = process.argv[2];
  const zoneId = process.env.CF_ZONE_ID;
  const apiToken = process.env.CF_API_TOKEN;

  if (!zoneId || !apiToken) {
    console.error('Error: CF_ZONE_ID and CF_API_TOKEN environment variables required');
    process.exit(1);
  }

  async function main() {
    switch (command) {
      case 'all':
        console.log('Purging entire cache...');
        const allResult = await purgeEverything(zoneId!, apiToken!);
        console.log(allResult.success ? 'Success!' : `Failed: ${allResult.errors?.join(', ')}`);
        break;

      case 'tags':
        const tags = process.argv.slice(3);
        if (tags.length === 0) {
          console.error('Usage: bun purge.ts tags <tag1> <tag2> ...');
          process.exit(1);
        }
        console.log(`Purging tags: ${tags.join(', ')}...`);
        const tagsResult = await purgeByTags(zoneId!, apiToken!, tags);
        console.log(tagsResult.success ? 'Success!' : `Failed: ${tagsResult.errors?.join(', ')}`);
        break;

      default:
        console.log('Usage:');
        console.log('  bun purge.ts all              - Purge entire cache');
        console.log('  bun purge.ts tags <tags...>   - Purge by cache tags');
        process.exit(1);
    }
  }

  main().catch(console.error);
}
