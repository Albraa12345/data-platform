#!/bin/bash
# ============================================
# Pipeline Verification Script
# ============================================
# Verifies end-to-end data flow through the pipeline

set -e

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "============================================"
echo "Data Pipeline Verification"
echo "============================================"

# Check Kafka Connect status
echo ""
echo "1. Checking Kafka Connect Connectors..."
echo "----------------------------------------"
connectors=$(curl -s "${KAFKA_CONNECT_URL}/connectors")
echo "Connectors: ${connectors}"

for connector in $(echo "${connectors}" | tr -d '[]"' | tr ',' ' '); do
    status=$(curl -s "${KAFKA_CONNECT_URL}/connectors/${connector}/status" | grep -o '"state":"[^"]*"' | head -1)
    echo "  ${connector}: ${status}"
done

# Check ClickHouse Bronze Layer
echo ""
echo "2. Checking Bronze Layer (Kafka Ingestion)..."
echo "----------------------------------------------"

echo "Bronze Users:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT count() as count, max(source_timestamp) as latest FROM analytics.bronze_users FORMAT PrettyCompact"

echo ""
echo "Bronze Events:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT count() as count, max(event_timestamp) as latest FROM analytics.bronze_events FORMAT PrettyCompact"

# Check Silver Layer
echo ""
echo "3. Checking Silver Layer (Transformed Data)..."
echo "-----------------------------------------------"

echo "Silver Users (Current State):"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT count() as total, countIf(is_deleted=0) as active, countIf(is_deleted=1) as deleted FROM analytics.silver_users FINAL FORMAT PrettyCompact"

echo ""
echo "Silver Events:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT count() as total, uniq(user_id) as unique_users, uniq(event_type) as event_types FROM analytics.silver_events FORMAT PrettyCompact"

# Check Gold Layer
echo ""
echo "4. Checking Gold Layer (Aggregated Data)..."
echo "--------------------------------------------"

echo "Gold User Activity:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT count() as rows, sum(event_count) as total_events, min(activity_date) as min_date, max(activity_date) as max_date FROM analytics.gold_user_activity FINAL FORMAT PrettyCompact"

# Sample data check
echo ""
echo "5. Sample Data Verification..."
echo "------------------------------"

echo "Sample Silver Users:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT user_id, full_name, email, is_deleted, last_cdc_operation FROM analytics.v_silver_users_all LIMIT 5 FORMAT PrettyCompact"

echo ""
echo "Sample Silver Events:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SELECT event_id, user_id, event_type, event_timestamp FROM analytics.silver_events ORDER BY event_timestamp DESC LIMIT 5 FORMAT PrettyCompact"

echo ""
echo "============================================"
echo "Pipeline Verification Complete!"
echo "============================================"
