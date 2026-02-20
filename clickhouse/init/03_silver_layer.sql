-- ============================================
-- SILVER LAYER - Cleansed & Deduplicated Data
-- Current state models with CDC correctness
-- ============================================

-- ============================================
-- Silver Users: Current State with CDC
-- ============================================
-- Requirements:
-- 1. Maintain current state only (latest version per user)
-- 2. Handle INSERT, UPDATE correctly
-- 3. Handle DELETE as soft delete (is_deleted = 1)
-- 4. Use ReplacingMergeTree for deduplication
-- 5. Version-based deduplication for CDC ordering

CREATE TABLE IF NOT EXISTS analytics.silver_users (
    -- Business keys
    user_id             Int32,
    
    -- User attributes (current state)
    full_name           String,
    email               String,
    created_at          DateTime64(3, 'UTC'),
    updated_at          DateTime64(3, 'UTC'),
    
    -- Soft delete flag (DELETE operations set this to 1)
    is_deleted          UInt8 DEFAULT 0,
    
    -- CDC tracking
    last_cdc_operation  String,
    last_cdc_timestamp  DateTime64(3, 'UTC'),
    
    -- Version for ReplacingMergeTree (higher = newer)
    -- Uses source timestamp for proper CDC ordering
    _version            UInt64,
    
    -- Audit fields
    _updated_at         DateTime64(3, 'UTC') DEFAULT now64(3)
    
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id)
SETTINGS index_granularity = 8192;

-- Materialized View: Bronze → Silver Users transformation
-- Handles INSERT, UPDATE, DELETE with proper versioning
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.silver_users_mv TO analytics.silver_users AS
SELECT
    user_id,
    
    -- For DELETE operations, preserve last known values but mark as deleted
    -- The ReplacingMergeTree will keep the highest version
    full_name,
    email,
    created_at,
    updated_at,
    
    -- Soft delete: DELETE operations set is_deleted = 1
    is_deleted,
    
    -- CDC tracking
    cdc_operation AS last_cdc_operation,
    cdc_timestamp AS last_cdc_timestamp,
    
    -- Version based on source timestamp (ensures CDC order correctness)
    _version,
    
    _ingested_at AS _updated_at
FROM analytics.bronze_users;

-- ============================================
-- View for querying current active users
-- This is the main query interface for silver_users
-- ============================================
CREATE VIEW IF NOT EXISTS analytics.v_silver_users_current AS
SELECT
    user_id,
    full_name,
    email,
    created_at,
    updated_at,
    is_deleted,
    last_cdc_operation,
    last_cdc_timestamp,
    _version,
    _updated_at
FROM analytics.silver_users
FINAL  -- Forces deduplication at query time
WHERE is_deleted = 0;

-- View for all users including soft-deleted (for audit)
CREATE VIEW IF NOT EXISTS analytics.v_silver_users_all AS
SELECT
    user_id,
    full_name,
    email,
    created_at,
    updated_at,
    is_deleted,
    last_cdc_operation,
    last_cdc_timestamp,
    _version,
    _updated_at
FROM analytics.silver_users
FINAL;


-- ============================================
-- Silver Events: Append-Only Event Store
-- ============================================
-- Requirements:
-- 1. Store raw MongoDB events
-- 2. Append-only (events are immutable)
-- 3. Partition by date for efficient queries
-- 4. Optimized for time-range queries

CREATE TABLE IF NOT EXISTS analytics.silver_events (
    -- Event identification
    event_id            String,
    
    -- Event data
    user_id             Int32,
    event_type          LowCardinality(String),
    event_timestamp     DateTime64(3, 'UTC'),
    event_date          Date MATERIALIZED toDate(event_timestamp),
    
    -- Event metadata (stored as JSON for flexibility)
    metadata            String,
    
    -- Extracted common metadata fields for efficient filtering
    device              LowCardinality(String) DEFAULT '',
    os                  LowCardinality(String) DEFAULT '',
    browser             LowCardinality(String) DEFAULT '',
    page                String DEFAULT '',
    product_id          String DEFAULT '',
    order_id            String DEFAULT '',
    
    -- CDC metadata
    cdc_operation       LowCardinality(String),
    cdc_timestamp       DateTime64(3, 'UTC'),
    
    -- Audit
    _ingested_at        DateTime64(3, 'UTC') DEFAULT now64(3)
    
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_timestamp)
ORDER BY (event_date, user_id, event_timestamp, event_id)
TTL toDate(event_timestamp) + INTERVAL 2 YEAR
SETTINGS index_granularity = 8192;

-- Secondary indexes for common query patterns
ALTER TABLE analytics.silver_events ADD INDEX IF NOT EXISTS idx_event_type (event_type) TYPE set(100) GRANULARITY 4;
ALTER TABLE analytics.silver_events ADD INDEX IF NOT EXISTS idx_user_id (user_id) TYPE minmax GRANULARITY 4;
ALTER TABLE analytics.silver_events ADD INDEX IF NOT EXISTS idx_product_id (product_id) TYPE bloom_filter(0.01) GRANULARITY 4;

-- Materialized View: Bronze → Silver Events transformation
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.silver_events_mv TO analytics.silver_events AS
SELECT
    event_id,
    user_id,
    event_type,
    event_timestamp,
    metadata,
    
    -- Extract common metadata fields
    JSONExtractString(metadata, 'device') AS device,
    JSONExtractString(metadata, 'os') AS os,
    JSONExtractString(metadata, 'browser') AS browser,
    JSONExtractString(metadata, 'page') AS page,
    JSONExtractString(metadata, 'product_id') AS product_id,
    JSONExtractString(metadata, 'order_id') AS order_id,
    
    cdc_operation,
    cdc_timestamp,
    _ingested_at
FROM analytics.bronze_events
WHERE is_deleted = 0;  -- Filter out deleted events at silver layer

-- ============================================
-- Utility: Force optimization of silver tables
-- Run periodically to merge parts and deduplicate
-- ============================================

-- Note: Run these manually or via scheduled task
-- OPTIMIZE TABLE analytics.silver_users FINAL;
-- OPTIMIZE TABLE analytics.silver_events FINAL;

-- Log initialization
SELECT 'Silver layer tables created successfully' AS status;
