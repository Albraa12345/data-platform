-- ============================================
-- BRONZE LAYER - Kafka Engine Tables
-- Raw CDC data ingestion from Kafka topics
-- ============================================

-- ============================================
-- Bronze: PostgreSQL Users CDC Stream
-- ============================================

-- Kafka Engine table for real-time consumption
CREATE TABLE IF NOT EXISTS analytics.bronze_users_kafka (
    -- CDC payload fields (after ExtractNewRecordState transform)
    user_id         Nullable(Int32),
    full_name       Nullable(String),
    email           Nullable(String),
    created_at      Nullable(String),
    updated_at      Nullable(String),
    
    -- CDC metadata fields added by Debezium transform
    __op            Nullable(String),      -- Operation: c=create, u=update, d=delete, r=read(snapshot)
    __ts_ms         Nullable(Int64),       -- Debezium processing timestamp
    __source_ts_ms  Nullable(Int64),       -- Source database timestamp
    __deleted       Nullable(String)       -- Soft delete marker from rewrite mode
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'postgres.public.users',
    kafka_group_name = 'clickhouse_users_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1,
    kafka_max_block_size = 65536,
    kafka_skip_broken_messages = 100,
    kafka_commit_every_batch = 0;

-- Materialized View to persist Kafka data to Bronze table
CREATE TABLE IF NOT EXISTS analytics.bronze_users (
    user_id         Int32,
    full_name       String,
    email           String,
    created_at      DateTime64(3, 'UTC'),
    updated_at      DateTime64(3, 'UTC'),
    
    -- CDC metadata
    cdc_operation   String,
    cdc_timestamp   DateTime64(3, 'UTC'),
    source_timestamp DateTime64(3, 'UTC'),
    is_deleted      UInt8,
    
    -- Ingestion metadata
    _ingested_at    DateTime64(3, 'UTC') DEFAULT now64(3),
    _kafka_offset   UInt64 DEFAULT 0,
    _version        UInt64 DEFAULT toUnixTimestamp64Milli(now64(3))
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(source_timestamp)
ORDER BY (user_id, _version)
TTL toDate(source_timestamp) + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Materialized View to move data from Kafka to Bronze
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.bronze_users_mv TO analytics.bronze_users AS
SELECT
    assumeNotNull(user_id) AS user_id,
    coalesce(full_name, '') AS full_name,
    coalesce(email, '') AS email,
    parseDateTime64BestEffortOrZero(coalesce(created_at, '1970-01-01'), 3, 'UTC') AS created_at,
    parseDateTime64BestEffortOrZero(coalesce(updated_at, '1970-01-01'), 3, 'UTC') AS updated_at,
    
    -- Map CDC operation
    CASE 
        WHEN __op = 'c' THEN 'INSERT'
        WHEN __op = 'u' THEN 'UPDATE'
        WHEN __op = 'd' THEN 'DELETE'
        WHEN __op = 'r' THEN 'SNAPSHOT'
        ELSE 'UNKNOWN'
    END AS cdc_operation,
    
    fromUnixTimestamp64Milli(coalesce(__ts_ms, 0)) AS cdc_timestamp,
    fromUnixTimestamp64Milli(coalesce(__source_ts_ms, __ts_ms, 0)) AS source_timestamp,
    
    -- Handle soft deletes
    if(__deleted = 'true' OR __op = 'd', 1, 0) AS is_deleted,
    
    now64(3) AS _ingested_at,
    toUInt64(0) AS _kafka_offset,
    toUnixTimestamp64Milli(now64(3)) AS _version
FROM analytics.bronze_users_kafka
WHERE user_id IS NOT NULL;


-- ============================================
-- Bronze: MongoDB Events CDC Stream
-- ============================================

-- Kafka Engine table for MongoDB events
CREATE TABLE IF NOT EXISTS analytics.bronze_events_kafka (
    -- MongoDB document ID
    _id                 Nullable(String),
    
    -- Event fields (flattened by ExtractNewDocumentState)
    event_id            Nullable(String),
    user_id             Nullable(Int32),
    event_type          Nullable(String),
    event_timestamp     Nullable(Int64),  -- Unix milliseconds from MongoDB
    
    -- Flattened metadata object
    metadata_device     Nullable(String),
    metadata_os         Nullable(String),
    metadata_browser    Nullable(String),
    metadata_page       Nullable(String),
    metadata_category   Nullable(String),
    metadata_query      Nullable(String),
    metadata_results_count Nullable(Int32),
    metadata_element    Nullable(String),
    metadata_product_id Nullable(String),
    metadata_quantity   Nullable(Int32),
    metadata_price      Nullable(Float64),
    metadata_order_id   Nullable(String),
    metadata_total      Nullable(Float64),
    metadata_items      Nullable(Int32),
    metadata_payment_method Nullable(String),
    metadata_referrer   Nullable(String),
    metadata_campaign   Nullable(String),
    metadata_session_duration_minutes Nullable(Int32),
    metadata_first_visit Nullable(UInt8),
    
    -- CDC metadata
    __op                Nullable(String),
    __ts_ms             Nullable(Int64),
    __deleted           Nullable(UInt8)
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'mongo.commerce.events',
    kafka_group_name = 'clickhouse_events_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1,
    kafka_max_block_size = 65536,
    kafka_skip_broken_messages = 100,
    kafka_commit_every_batch = 0;

-- Bronze Events persistent storage
CREATE TABLE IF NOT EXISTS analytics.bronze_events (
    event_id            String,
    user_id             Int32,
    event_type          String,
    event_timestamp     DateTime64(3, 'UTC'),
    
    -- Metadata as JSON for flexibility
    metadata            String,
    
    -- CDC metadata
    cdc_operation       String,
    cdc_timestamp       DateTime64(3, 'UTC'),
    is_deleted          UInt8,
    
    -- Ingestion metadata
    _ingested_at        DateTime64(3, 'UTC') DEFAULT now64(3),
    _version            UInt64 DEFAULT toUnixTimestamp64Milli(now64(3))
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_timestamp)
ORDER BY (event_timestamp, user_id, event_id)
TTL toDate(event_timestamp) + INTERVAL 365 DAY
SETTINGS index_granularity = 8192;

-- Materialized View for MongoDB events
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.bronze_events_mv TO analytics.bronze_events AS
SELECT
    coalesce(event_id, _id, generateUUIDv4()::String) AS event_id,
    assumeNotNull(user_id) AS user_id,
    coalesce(event_type, 'unknown') AS event_type,
    fromUnixTimestamp64Milli(coalesce(event_timestamp, 0)) AS event_timestamp,
    
    -- Reconstruct metadata as JSON
    toJSONString(map(
        'device', coalesce(metadata_device, ''),
        'os', coalesce(metadata_os, ''),
        'browser', coalesce(metadata_browser, ''),
        'page', coalesce(metadata_page, ''),
        'category', coalesce(metadata_category, ''),
        'query', coalesce(metadata_query, ''),
        'results_count', toString(coalesce(metadata_results_count, 0)),
        'element', coalesce(metadata_element, ''),
        'product_id', coalesce(metadata_product_id, ''),
        'quantity', toString(coalesce(metadata_quantity, 0)),
        'price', toString(coalesce(metadata_price, 0)),
        'order_id', coalesce(metadata_order_id, ''),
        'total', toString(coalesce(metadata_total, 0)),
        'items', toString(coalesce(metadata_items, 0)),
        'payment_method', coalesce(metadata_payment_method, ''),
        'referrer', coalesce(metadata_referrer, ''),
        'campaign', coalesce(metadata_campaign, '')
    )) AS metadata,
    
    CASE 
        WHEN __op = 'c' THEN 'INSERT'
        WHEN __op = 'u' THEN 'UPDATE'
        WHEN __op = 'd' THEN 'DELETE'
        WHEN __op = 'r' THEN 'SNAPSHOT'
        ELSE 'UNKNOWN'
    END AS cdc_operation,
    
    fromUnixTimestamp64Milli(coalesce(__ts_ms, 0)) AS cdc_timestamp,
    if(__deleted = 'true' OR __op = 'd', 1, 0) AS is_deleted,
    
    now64(3) AS _ingested_at,
    toUnixTimestamp64Milli(now64(3)) AS _version
FROM analytics.bronze_events_kafka
WHERE user_id IS NOT NULL;

-- Log initialization
SELECT 'Bronze layer tables created successfully' AS status;
