-- ============================================
-- PostgreSQL Initialization Script
-- Commerce Database - Users Table with CDC
-- ============================================

-- Create the users table with proper constraints
CREATE TABLE IF NOT EXISTS users (
    user_id         SERIAL PRIMARY KEY,
    full_name       VARCHAR(255) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Create index on created_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Create index on updated_at for CDC tracking
CREATE INDEX IF NOT EXISTS idx_users_updated_at ON users(updated_at);

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to auto-update updated_at on row changes
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Logical Replication Setup for Debezium CDC
-- ============================================

-- Create publication for CDC (Debezium will use this)
-- Note: wal_level=logical is set in docker-compose command
DROP PUBLICATION IF EXISTS debezium_publication;
CREATE PUBLICATION debezium_publication FOR TABLE users;

-- Create a replication slot for Debezium (optional - Debezium can create its own)
-- SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Grant necessary permissions for the postgres user (used by Debezium)
ALTER TABLE users REPLICA IDENTITY FULL;

-- ============================================
-- Insert Sample Data
-- ============================================

INSERT INTO users (full_name, email, created_at, updated_at) VALUES
    ('Alice Johnson', 'alice.johnson@example.com', '2024-01-15 10:30:00+00', '2024-01-15 10:30:00+00'),
    ('Bob Smith', 'bob.smith@example.com', '2024-01-16 14:45:00+00', '2024-01-16 14:45:00+00'),
    ('Carol Williams', 'carol.williams@example.com', '2024-01-17 09:15:00+00', '2024-01-17 09:15:00+00'),
    ('David Brown', 'david.brown@example.com', '2024-01-18 16:20:00+00', '2024-01-18 16:20:00+00'),
    ('Emma Davis', 'emma.davis@example.com', '2024-01-19 11:00:00+00', '2024-01-19 11:00:00+00'),
    ('Frank Miller', 'frank.miller@example.com', '2024-01-20 08:30:00+00', '2024-01-20 08:30:00+00'),
    ('Grace Wilson', 'grace.wilson@example.com', '2024-01-21 13:45:00+00', '2024-01-21 13:45:00+00'),
    ('Henry Taylor', 'henry.taylor@example.com', '2024-01-22 15:10:00+00', '2024-01-22 15:10:00+00'),
    ('Ivy Anderson', 'ivy.anderson@example.com', '2024-01-23 10:00:00+00', '2024-01-23 10:00:00+00'),
    ('Jack Thomas', 'jack.thomas@example.com', '2024-01-24 12:30:00+00', '2024-01-24 12:30:00+00');

-- ============================================
-- Verification Queries (for debugging)
-- ============================================

-- Verify table structure
-- \d users

-- Verify replication identity
-- SELECT relname, relreplident FROM pg_class WHERE relname = 'users';

-- Verify publication
-- SELECT * FROM pg_publication;
-- SELECT * FROM pg_publication_tables;

-- Log successful initialization
DO $$
BEGIN
    RAISE NOTICE 'PostgreSQL commerce database initialized successfully';
    RAISE NOTICE 'Users table created with % rows', (SELECT COUNT(*) FROM users);
    RAISE NOTICE 'Logical replication configured for CDC';
END $$;
