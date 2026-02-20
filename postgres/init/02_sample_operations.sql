-- ============================================
-- Sample CDC Operations Script
-- Demonstrates INSERT, UPDATE, DELETE operations
-- Run these AFTER Debezium connector is configured
-- ============================================

-- This script is meant to be run manually to generate CDC events
-- Execute these commands one-by-one to see CDC in action

-- ============================================
-- UPDATE Operations (modify existing records)
-- ============================================

-- Update user email
UPDATE users 
SET email = 'alice.j@newdomain.com' 
WHERE user_id = 1;

-- Update user full name
UPDATE users 
SET full_name = 'Robert Smith Jr.' 
WHERE user_id = 2;

-- Bulk update - mark users as verified (simulated)
UPDATE users 
SET updated_at = CURRENT_TIMESTAMP 
WHERE user_id IN (3, 4, 5);

-- ============================================
-- INSERT Operations (new records)
-- ============================================

INSERT INTO users (full_name, email) VALUES
    ('Katherine Lee', 'katherine.lee@example.com'),
    ('Liam Martinez', 'liam.martinez@example.com'),
    ('Mia Garcia', 'mia.garcia@example.com');

-- ============================================
-- DELETE Operations (remove records)
-- ============================================

-- Delete a single user
DELETE FROM users WHERE user_id = 10;

-- Delete users with specific condition
DELETE FROM users WHERE email LIKE '%newdomain%';

-- ============================================
-- Complex Operation Sequence
-- ============================================

-- Insert, Update, then Delete (to test CDC ordering)
INSERT INTO users (full_name, email) VALUES ('Temp User', 'temp@example.com');

UPDATE users SET full_name = 'Temporary User Updated' WHERE email = 'temp@example.com';

DELETE FROM users WHERE email = 'temp@example.com';

-- ============================================
-- Verification
-- ============================================

SELECT 
    user_id,
    full_name,
    email,
    created_at,
    updated_at
FROM users
ORDER BY user_id;
