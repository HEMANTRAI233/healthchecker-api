-- Initial schema for healthchecker-api

CREATE TABLE IF NOT EXISTS health_check_log (
    id         SERIAL PRIMARY KEY,
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    db_version TEXT        NOT NULL
);
