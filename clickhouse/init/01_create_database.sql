-- ============================================
-- ClickHouse Database Initialization
-- Analytics Database Setup
-- ============================================

-- Create the analytics database
CREATE DATABASE IF NOT EXISTS analytics;

-- Create a staging database for intermediate processing
CREATE DATABASE IF NOT EXISTS staging;

-- Log initialization
SELECT 'Databases created: analytics, staging' AS status;
