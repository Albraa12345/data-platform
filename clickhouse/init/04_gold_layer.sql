-- ============================================
-- GOLD LAYER - Aggregated Analytics Tables
-- Business-ready metrics and KPIs
-- ============================================

-- ============================================
-- Gold: Daily User Activity Aggregations
-- ============================================
-- Requirements:
-- 1. Daily aggregated table with user_id, event_count, last_event_timestamp, activity_date
-- 2. Fully idempotent (re-running produces same result)
-- 3. Support backfilling historical data
-- 4. Avoid duplicates using ReplacingMergeTree
-- 5. Partition-aware for efficient updates

CREATE TABLE IF NOT EXISTS analytics.gold_user_activity (
    -- Grain: one row per user per day
    activity_date       Date,
    user_id             Int32,
    
    -- Aggregated metrics
    event_count         UInt64,
    last_event_timestamp DateTime64(3, 'UTC'),
    
    -- Event type breakdown
    page_view_count     UInt64 DEFAULT 0,
    click_count         UInt64 DEFAULT 0,
    purchase_count      UInt64 DEFAULT 0,
    search_count        UInt64 DEFAULT 0,
    add_to_cart_count   UInt64 DEFAULT 0,
    login_count         UInt64 DEFAULT 0,
    
    -- User context (from silver_users at time of aggregation)
    user_full_name      String DEFAULT '',
    user_email          String DEFAULT '',
    user_is_active      UInt8 DEFAULT 1,
    
    -- Metadata
    _computed_at        DateTime64(3, 'UTC') DEFAULT now64(3),
    _version            UInt64 DEFAULT toUnixTimestamp64Milli(now64(3))
    
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(activity_date)
ORDER BY (activity_date, user_id)
SETTINGS index_granularity = 8192;

-- Secondary indexes
ALTER TABLE analytics.gold_user_activity ADD INDEX IF NOT EXISTS idx_user_id (user_id) TYPE minmax GRANULARITY 4;
ALTER TABLE analytics.gold_user_activity ADD INDEX IF NOT EXISTS idx_event_count (event_count) TYPE minmax GRANULARITY 4;

-- ============================================
-- View: Current Gold User Activity (deduplicated)
-- ============================================
CREATE VIEW IF NOT EXISTS analytics.v_gold_user_activity AS
SELECT
    activity_date,
    user_id,
    event_count,
    last_event_timestamp,
    page_view_count,
    click_count,
    purchase_count,
    search_count,
    add_to_cart_count,
    login_count,
    user_full_name,
    user_email,
    user_is_active,
    _computed_at,
    _version
FROM analytics.gold_user_activity
FINAL;


-- ============================================
-- Staging table for batch processing
-- Used by Airflow for idempotent inserts
-- ============================================
CREATE TABLE IF NOT EXISTS staging.gold_user_activity_staging (
    activity_date       Date,
    user_id             Int32,
    event_count         UInt64,
    last_event_timestamp DateTime64(3, 'UTC'),
    page_view_count     UInt64,
    click_count         UInt64,
    purchase_count      UInt64,
    search_count        UInt64,
    add_to_cart_count   UInt64,
    login_count         UInt64,
    user_full_name      String,
    user_email          String,
    user_is_active      UInt8,
    _computed_at        DateTime64(3, 'UTC'),
    _version            UInt64
) ENGINE = MergeTree()
ORDER BY (activity_date, user_id)
TTL toDate(_computed_at) + INTERVAL 7 DAY;


-- ============================================
-- Additional Gold Tables for Analytics
-- ============================================

-- Gold: Daily Platform Metrics
CREATE TABLE IF NOT EXISTS analytics.gold_daily_metrics (
    metric_date         Date,
    
    -- User metrics
    total_active_users  UInt64,
    new_users           UInt64,
    
    -- Event metrics  
    total_events        UInt64,
    total_page_views    UInt64,
    total_purchases     UInt64,
    total_revenue       Float64,
    
    -- Engagement
    avg_events_per_user Float64,
    avg_session_duration_minutes Float64,
    
    -- Metadata
    _computed_at        DateTime64(3, 'UTC') DEFAULT now64(3),
    _version            UInt64 DEFAULT toUnixTimestamp64Milli(now64(3))
    
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(metric_date)
ORDER BY (metric_date)
SETTINGS index_granularity = 8192;


-- Gold: User Lifetime Metrics (SCD Type 1 - latest only)
CREATE TABLE IF NOT EXISTS analytics.gold_user_lifetime (
    user_id                 Int32,
    
    -- Lifetime metrics
    first_seen_date         Date,
    last_seen_date          Date,
    total_lifetime_events   UInt64,
    total_purchases         UInt64,
    total_revenue           Float64,
    days_active             UInt32,
    
    -- Current state
    is_active               UInt8,
    
    -- Metadata
    _computed_at            DateTime64(3, 'UTC') DEFAULT now64(3),
    _version                UInt64 DEFAULT toUnixTimestamp64Milli(now64(3))
    
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id)
SETTINGS index_granularity = 8192;


-- ============================================
-- Stored procedure alternatives (ClickHouse uses INSERT...SELECT)
-- These are example queries for batch processing
-- ============================================

-- Example: Compute daily user activity for a specific date
-- This query is used by the Airflow DAG
/*
INSERT INTO analytics.gold_user_activity
SELECT
    toDate(se.event_timestamp) AS activity_date,
    se.user_id,
    count() AS event_count,
    max(se.event_timestamp) AS last_event_timestamp,
    countIf(se.event_type = 'page_view') AS page_view_count,
    countIf(se.event_type = 'click') AS click_count,
    countIf(se.event_type = 'purchase') AS purchase_count,
    countIf(se.event_type = 'search') AS search_count,
    countIf(se.event_type = 'add_to_cart') AS add_to_cart_count,
    countIf(se.event_type = 'login') AS login_count,
    coalesce(su.full_name, '') AS user_full_name,
    coalesce(su.email, '') AS user_email,
    if(su.is_deleted = 0, 1, 0) AS user_is_active,
    now64(3) AS _computed_at,
    toUnixTimestamp64Milli(now64(3)) AS _version
FROM analytics.silver_events AS se
LEFT JOIN analytics.v_silver_users_all AS su ON se.user_id = su.user_id
WHERE toDate(se.event_timestamp) = '2024-01-15'  -- Target date
GROUP BY
    activity_date,
    se.user_id,
    su.full_name,
    su.email,
    su.is_deleted;
*/

-- Log initialization
SELECT 'Gold layer tables created successfully' AS status;
