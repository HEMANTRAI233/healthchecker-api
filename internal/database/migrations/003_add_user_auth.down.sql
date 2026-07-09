ALTER TABLE application_users DROP CONSTRAINT IF EXISTS application_users_username_unique;
ALTER TABLE application_users DROP COLUMN IF EXISTS password_hash;
