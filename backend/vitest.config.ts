import path from 'node:path';
import { defineWorkersConfig, readD1Migrations } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig(async () => {
  const migrationsPath = path.join(__dirname, 'migrations');
  const migrations = await readD1Migrations(migrationsPath);

  return {
    test: {
      setupFiles: ['./test/apply-migrations.ts'],
      poolOptions: {
        workers: {
          isolatedStorage: false,
          wrangler: { configPath: './wrangler.jsonc' },
          miniflare: {
            unsafeEphemeralDurableObjects: true,
            bindings: {
              TEST_MIGRATIONS: migrations,
              ADMIN_BOOTSTRAP_SECRET: 'test-bootstrap-secret',
              SESSION_SIGNING_KEY: 'test-session-signing-key-0123456789',
              PUSH_TOKEN_ENCRYPTION_KEY: 'test-push-token-encryption-key-0123456789',
            },
            ratelimits: {
              RATE_LIMIT_JOIN: { simple: { limit: 20, period: 60 } },
              RATE_LIMIT_INVITE: { simple: { limit: 30, period: 60 } },
              RATE_LIMIT_BOOTSTRAP: { simple: { limit: 5, period: 60 } },
            },
          },
        },
      },
    },
  };
});
