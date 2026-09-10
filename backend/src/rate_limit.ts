import type { Env } from './types';

/**
 * Thin wrapper around the Cloudflare Workers native Rate Limiting binding.
 * The binding is optional: local dev/test environments that don't declare
 * `ratelimits` in wrangler.jsonc simply skip enforcement instead of failing
 * closed, so this must never be the only defense for a sensitive endpoint —
 * pair it with the invite/token checks that already exist.
 */
export interface RateLimiterBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export function clientIp(request: Request): string {
  return request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || 'unknown';
}

export async function rateLimited(env: Env, bucket: string, discriminator: string): Promise<boolean> {
  const limiter = (env as unknown as Record<string, RateLimiterBinding | undefined>)[bucket];
  if (!limiter) return false;
  try {
    const result = await limiter.limit({ key: discriminator });
    return !result.success;
  } catch {
    return false;
  }
}
