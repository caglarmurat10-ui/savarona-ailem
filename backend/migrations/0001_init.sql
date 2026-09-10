PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS app_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS families (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS members (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('owner','admin','member')),
  created_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_members_family ON members(family_id);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('android','ios','other')),
  token_hash TEXT NOT NULL UNIQUE,
  last_seen_at INTEGER,
  battery_pct INTEGER,
  permission_state TEXT,
  app_state TEXT,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_devices_family ON devices(family_id);
CREATE INDEX IF NOT EXISTS idx_devices_member ON devices(member_id);

CREATE TABLE IF NOT EXISTS locations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  family_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  captured_at INTEGER NOT NULL,
  received_at INTEGER NOT NULL,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  accuracy_m REAL,
  altitude_m REAL,
  speed_mps REAL,
  heading_deg REAL,
  battery_pct INTEGER,
  activity TEXT,
  source TEXT NOT NULL DEFAULT 'gps',
  sequence_no INTEGER,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_locations_member_time ON locations(family_id, member_id, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_device_time ON locations(device_id, captured_at DESC);

CREATE TABLE IF NOT EXISTS invites (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  code_hash TEXT NOT NULL UNIQUE,
  created_by_member_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  member_id TEXT,
  device_id TEXT,
  type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'info',
  payload_json TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_events_family_time ON events(family_id, created_at DESC);

CREATE TABLE IF NOT EXISTS geofences (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  name TEXT NOT NULL,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  radius_m REAL NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
);
