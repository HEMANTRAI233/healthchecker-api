-- Add password_hash column for bcrypt-based authentication
ALTER TABLE application_users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255) NOT NULL DEFAULT '';

-- Ensure username is unique so login lookups are unambiguous
ALTER TABLE application_users ADD CONSTRAINT application_users_username_unique UNIQUE (username);
