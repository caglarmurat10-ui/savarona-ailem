import type { RateLimiterBinding } from './rate_limit';

export interface Env {
  DB: D1Database;
  FAMILY_LIVE: DurableObjectNamespace;
  ADMIN_BOOTSTRAP_SECRET: string;
  SESSION_SIGNING_KEY: string;
  PUSH_TOKEN_ENCRYPTION_KEY: string;
  APP_ENV: string;
  OFFLINE_WARN_SECONDS: string;
  OFFLINE_SECONDS: string;
  RATE_LIMIT_JOIN?: RateLimiterBinding;
  RATE_LIMIT_INVITE?: RateLimiterBinding;
  RATE_LIMIT_BOOTSTRAP?: RateLimiterBinding;
}

export interface DevicePrincipal {
  deviceId: string;
  familyId: string;
  memberId: string;
  memberName: string;
  role: 'owner' | 'admin' | 'member';
}

export interface LocationPayload {
  captured_at: number;
  lat: number;
  lng: number;
  accuracy_m?: number | null;
  altitude_m?: number | null;
  speed_mps?: number | null;
  heading_deg?: number | null;
  battery_pct?: number | null;
  activity?: string | null;
  sequence_no?: number | null;
}
