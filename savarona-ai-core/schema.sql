CREATE TABLE IF NOT EXISTS agent_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  type TEXT NOT NULL,
  severity TEXT NOT NULL,
  message TEXT NOT NULL,
  details_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_agent_events_project_created
  ON agent_events(project_id, created_at DESC);

CREATE TABLE IF NOT EXISTS agent_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  result_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_agent_runs_project_created
  ON agent_runs(project_id, created_at DESC);

CREATE TABLE IF NOT EXISTS improvement_proposals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope TEXT NOT NULL,
  proposal_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('proposed', 'approved', 'rejected', 'applied', 'rolled_back')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at TEXT,
  applied_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_improvement_status_created
  ON improvement_proposals(status, created_at DESC);
