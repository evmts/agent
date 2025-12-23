/**
 * Cloudflare Workers environment bindings.
 */
export interface Env {
  ORIGIN_HOST: string;
  BUILD_VERSION: string;

  // Optional: Cloudflare API credentials for programmatic purge
  CF_ZONE_ID?: string;
  CF_API_TOKEN?: string;
}
