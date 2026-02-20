#!/bin/bash
# ============================================
# Debezium Connector Setup Script
# ============================================
# This script registers CDC connectors with Kafka Connect
# Run this AFTER all services are healthy

set -e

CONNECT_URL="http://localhost:8083"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "Debezium Connector Setup"
echo "============================================"

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect to be ready..."
max_attempts=60
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s "${CONNECT_URL}/connectors" > /dev/null 2>&1; then
        echo "Kafka Connect is ready!"
        break
    fi
    echo "Attempt $((attempt+1))/${max_attempts}: Kafka Connect not ready, waiting..."
    sleep 5
    attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "ERROR: Kafka Connect did not become ready in time"
    exit 1
fi

# Function to register a connector
register_connector() {
    local name=$1
    local config_file=$2
    
    echo ""
    echo "Registering connector: ${name}"
    echo "Config file: ${config_file}"
    
    # Check if connector already exists
    existing=$(curl -s "${CONNECT_URL}/connectors/${name}" | grep -c "error_code" || true)
    
    if [ "$existing" -eq 0 ]; then
        echo "Connector ${name} already exists. Deleting..."
        curl -s -X DELETE "${CONNECT_URL}/connectors/${name}"
        sleep 2
    fi
    
    # Register connector
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data @"${config_file}" \
        "${CONNECT_URL}/connectors")
    
    echo "Response: ${response}"
    
    # Verify connector status
    sleep 3
    status=$(curl -s "${CONNECT_URL}/connectors/${name}/status")
    echo "Connector status: ${status}"
}

# Register PostgreSQL connector
echo ""
echo "============================================"
echo "Setting up PostgreSQL CDC Connector"
echo "============================================"
register_connector "postgres-users-connector" "${PROJECT_ROOT}/debezium/connectors/postgres-connector.json"

# Wait before registering MongoDB connector
sleep 5

# Register MongoDB connector
echo ""
echo "============================================"
echo "Setting up MongoDB CDC Connector"
echo "============================================"
register_connector "mongodb-events-connector" "${PROJECT_ROOT}/debezium/connectors/mongodb-connector.json"

# List all connectors
echo ""
echo "============================================"
echo "Registered Connectors"
echo "============================================"
curl -s "${CONNECT_URL}/connectors" | python3 -m json.tool 2>/dev/null || curl -s "${CONNECT_URL}/connectors"

echo ""
echo "============================================"
echo "Connector Setup Complete!"
echo "============================================"
echo ""
echo "Monitor connectors at: ${CONNECT_URL}/connectors"
echo "Kafka UI available at: http://localhost:8081"
echo ""
