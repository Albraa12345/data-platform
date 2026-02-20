#!/bin/bash
# ============================================
# ClickHouse Initialization Script
# ============================================
# This script initializes the ClickHouse schema
# Run this AFTER ClickHouse is healthy

set -e

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLICKHOUSE_INIT_DIR="${PROJECT_ROOT}/clickhouse/init"

echo "============================================"
echo "ClickHouse Schema Initialization"
echo "============================================"

# Wait for ClickHouse to be ready
echo "Waiting for ClickHouse to be ready..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/ping" | grep -q "Ok"; then
        echo "ClickHouse is ready!"
        break
    fi
    echo "Attempt $((attempt+1))/${max_attempts}: ClickHouse not ready, waiting..."
    sleep 2
    attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "ERROR: ClickHouse did not become ready in time"
    exit 1
fi

# Function to execute SQL file
execute_sql_file() {
    local sql_file=$1
    echo ""
    echo "Executing: ${sql_file}"
    
    curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
        --data-binary @"${sql_file}" \
        -H "Content-Type: text/plain"
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Success"
    else
        echo "  ✗ Failed"
        return 1
    fi
}

# Execute initialization scripts in order
echo ""
echo "Executing initialization scripts..."

for sql_file in $(ls -1 "${CLICKHOUSE_INIT_DIR}"/*.sql | sort); do
    execute_sql_file "${sql_file}"
done

# Verify tables were created
echo ""
echo "============================================"
echo "Verifying Created Tables"
echo "============================================"

echo ""
echo "Analytics Database Tables:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SHOW TABLES FROM analytics FORMAT PrettyCompact"

echo ""
echo "Staging Database Tables:"
curl -s "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
    --data "SHOW TABLES FROM staging FORMAT PrettyCompact"

echo ""
echo "============================================"
echo "ClickHouse Initialization Complete!"
echo "============================================"
