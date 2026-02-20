#!/bin/bash

# ===========================================
# Data Platform Startup Script
# Run this from WSL terminal
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker-compose down

echo "=========================================="
echo "  Data Platform Startup"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_waiting() {
    echo -e "${YELLOW}[...]${NC} $1"
}

# Step 1: Start core infrastructure
echo ""
print_waiting "Starting Zookeeper, Kafka, PostgreSQL, MongoDB..."
docker-compose up -d zookeeper kafka postgres mongodb
sleep 15
print_status "Core infrastructure started"

# Step 2: Initialize MongoDB replica set
print_waiting "Initializing MongoDB replica set..."
docker-compose up -d mongodb-init
sleep 15
print_status "MongoDB replica set initialized"

# Step 3: Start Kafka Connect and ClickHouse
print_waiting "Starting Kafka Connect and ClickHouse..."
docker-compose up -d kafka-connect clickhouse kafka-ui
sleep 30
print_status "Kafka Connect and ClickHouse started"

# Step 4: Initialize Airflow
print_waiting "Starting Airflow PostgreSQL..."
docker-compose up -d airflow-postgres
sleep 10

print_waiting "Initializing Airflow database..."
docker-compose up -d airflow-init
sleep 45

print_waiting "Starting Airflow webserver and scheduler..."
docker-compose up -d airflow-webserver airflow-scheduler
sleep 30
print_status "Airflow started"

# Step 5: Register Debezium connectors
print_waiting "Registering Debezium connectors..."

# Check if Kafka Connect is ready
for i in {1..30}; do
    if curl -s http://localhost:8083/connectors > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Register PostgreSQL connector
curl -s -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/postgres-connector.json \
  http://localhost:8083/connectors > /dev/null 2>&1 || true

# Register MongoDB connector
curl -s -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/mongodb-connector.json \
  http://localhost:8083/connectors > /dev/null 2>&1 || true

print_status "Debezium connectors registered"

# Step 6: Insert test data
print_waiting "Inserting test data..."
docker exec -i mongodb mongosh --quiet < init-scripts/insert_mongo_events.js > /dev/null 2>&1 || true
print_status "Test data inserted"

# Final status
echo ""
echo "=========================================="
echo "  Platform Status"
echo "=========================================="
docker-compose ps

# Get WSL IP
WSL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo "  Access URLs"
echo "=========================================="
echo -e "${GREEN}Airflow UI:${NC}      http://${WSL_IP}:8080  (admin/admin)"
echo -e "${GREEN}Kafka UI:${NC}        http://${WSL_IP}:8081"
echo -e "${GREEN}ClickHouse:${NC}      http://${WSL_IP}:8123"
echo -e "${GREEN}ClickHouse Studio:${NC} http://${WSL_IP}:8123/"
echo -e "${GREEN}Kafka Connect:${NC}   http://${WSL_IP}:8083"
echo ""

# Verify data pipeline
echo "=========================================="
echo "  Data Pipeline Status"
echo "=========================================="
sleep 5
USERS=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_users" 2>/dev/null || echo "0")
EVENTS=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_events" 2>/dev/null || echo "0")
echo -e "PostgreSQL users in ClickHouse: ${GREEN}${USERS}${NC}"
echo -e "MongoDB events in ClickHouse:   ${GREEN}${EVENTS}${NC}"
echo ""
echo -e "${GREEN}Platform startup complete!${NC}"
