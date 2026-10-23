CREATE TABLE IF NOT EXISTS daily (
  install_id TEXT NOT NULL,
  day TEXT NOT NULL,
  received_at TEXT NOT NULL,
  app TEXT NOT NULL,
  build TEXT NOT NULL,
  os TEXT NOT NULL,
  arch TEXT NOT NULL,
  lang TEXT NOT NULL,
  report TEXT NOT NULL,
  PRIMARY KEY (install_id, day)
);
CREATE INDEX IF NOT EXISTS daily_day ON daily(day);
