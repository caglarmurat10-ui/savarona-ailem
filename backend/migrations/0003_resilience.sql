PRAGMA foreign_keys = ON;

-- Unique claim marker makes one-time invite consumption race-safe.
ALTER TABLE invites ADD COLUMN claim_id TEXT;

-- One stale event per offline episode; reset on heartbeat/location.
ALTER TABLE devices ADD COLUMN stale_notified_at INTEGER;

-- Push delivery needs a recoverable token. Keep its hash for lookup/dedup and
-- store the raw token only as AES-GCM ciphertext.
ALTER TABLE push_tokens ADD COLUMN token_ciphertext TEXT;
ALTER TABLE push_tokens ADD COLUMN token_iv TEXT;

-- Defense in depth for idempotent device uploads.
CREATE UNIQUE INDEX IF NOT EXISTS idx_locations_device_sequence
  ON locations(device_id, sequence_no)
  WHERE sequence_no IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_devices_stale_scan
  ON devices(last_seen_at, stale_notified_at)
  WHERE revoked_at IS NULL;
