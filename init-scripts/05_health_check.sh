#!/bin/bash
# ============================================
# Platform Health Check Script
# ============================================
# Comprehensive health check for all services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "Data Platform Health Check"
echo "============================================"
echo ""

check_service() {
    local name=$1
    local check_cmd=$2
    local expected=$3
    
    printf "%-25s" "$name:"
    
    result=$(eval "$check_cmd" 2>/dev/null || echo "FAILED")
    
    if [[ "$result" == *"$expected"* ]] || [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}✓ Healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Unhealthy${NC}"
        return 1
    fi
}

# Infrastructure Services
echo "Infrastructure Services"
echo "------------------------"

check_service "Zookeeper" \
    "echo ruok | nc localhost 2181" \
    "imok"

check_service "Kafka" \
    "docker-compose exec -T kafka kafka-broker-api-versions --bootstrap-server localhost:9092 2>&1 | head -1" \
    "ApiVersion"

check_service "Kafka Connect" \
    "curl -s http://localhost:8083/ | grep -o 'version'" \
    "version"

# Source Databases
echo ""
echo "Source Databases"
echo "-----------------"

check_service "PostgreSQL" \
    "docker-compose exec -T postgres pg_isready -U postgres" \
    "accepting"

check_service "MongoDB" \
    "docker-compose exec -T mongodb mongosh --eval 'db.runCommand({ping:1})' --quiet 2>/dev/null | grep -o 'ok'" \
    "ok"

# Analytics
echo ""
echo "Analytics Services"
echo "-------------------"

check_service "ClickHouse" \
    "curl -s http://localhost:8123/ping" \
    "Ok"

# Orchestration
echo ""
echo "Orchestration Services"
echo "-----------------------"

check_service "Airflow Webserver" \
    "curl -s http://localhost:8080/health | grep -o 'healthy'" \
    "healthy"

check_service "Airflow Scheduler" \
    "docker-compose exec -T airflow-scheduler airflow jobs check --job-type SchedulerJob 2>&1 | grep -c 'Found'" \
    "1"

# CDC Connectors
echo ""
echo "CDC Connectors"
echo "---------------"

pg_status=$(curl -s http://localhost:8083/connectors/postgres-users-connector/status 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 | grep -o 'RUNNING' || echo "NOT_RUNNING")
mongo_status=$(curl -s http://localhost:8083/connectors/mongodb-events-connector/status 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 | grep -o 'RUNNING' || echo "NOT_RUNNING")

printf "%-25s" "PostgreSQL Connector:"
if [[ "$pg_status" == "RUNNING" ]]; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}○ $pg_status${NC}"
fi

printf "%-25s" "MongoDB Connector:"
if [[ "$mongo_status" == "RUNNING" ]]; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}○ $mongo_status${NC}"
fi

# Data Flow Check
echo ""
echo "Data Flow Verification"
echo "-----------------------"

bronze_users=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_users" 2>/dev/null || echo "0")
bronze_events=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_events" 2>/dev/null || echo "0")
silver_users=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_users FINAL" 2>/dev/null || echo "0")
silver_events=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_events" 2>/dev/null || echo "0")
gold_activity=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.gold_user_activity FINAL" 2>/dev/null || echo "0")

echo "  Bronze Users:     $bronze_users rows"
echo "  Bronze Events:    $bronze_events rows"
echo "  Silver Users:     $silver_users rows"
echo "  Silver Events:    $silver_events rows"
echo "  Gold Activity:    $gold_activity rows"

# Summary
echo ""
echo "============================================"
echo "Health Check Complete"
echo "============================================"
