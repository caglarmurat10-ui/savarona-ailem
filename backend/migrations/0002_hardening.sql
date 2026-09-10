PRAGMA foreign_keys = ON;

ALTER TABLE devices ADD COLUMN last_sequence_no INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS push_tokens (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  family_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('fcm','apns')),
  token_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_tokens_device ON push_tokens(device_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS geofence_state (
  geofence_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  inside INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (geofence_id, member_id),
  FOREIGN KEY (geofence_id) REFERENCES geofences(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_geofences_family ON geofences(family_id) WHERE enabled = 1;
