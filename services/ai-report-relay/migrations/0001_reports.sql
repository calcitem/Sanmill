-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE reports (
  report_id TEXT PRIMARY KEY,
  delete_token_hash TEXT NOT NULL,
  category TEXT NOT NULL,
  task TEXT NOT NULL,
  surface TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  app_version TEXT NOT NULL,
  platform TEXT NOT NULL,
  locale TEXT NOT NULL,
  answer TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE INDEX reports_expires_at_idx ON reports(expires_at);

CREATE TABLE daily_category_totals (
  report_date TEXT NOT NULL,
  category TEXT NOT NULL,
  total INTEGER NOT NULL,
  PRIMARY KEY (report_date, category)
);

CREATE TABLE daily_rate_limits (
  report_date TEXT NOT NULL,
  requester_hash TEXT NOT NULL,
  total INTEGER NOT NULL,
  PRIMARY KEY (report_date, requester_hash)
);
