-- Add password_hash column for bcrypt-based authentication.
-- NULL is allowed so the column can be added safely to tables with existing rows;
-- the application-level seeder always supplies a non-NULL hash for every user it creates.
ALTER TABLE application_users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);

-- Ensure username is unique so login lookups are unambiguous
ALTER TABLE application_users ADD CONSTRAINT application_users_username_unique UNIQUE (username);
