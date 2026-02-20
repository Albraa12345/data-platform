#!/bin/bash

# ===========================================
# Data Platform Test Script
# Run this from WSL terminal after startup.sh
# ===========================================

# Removed set -e to prevent early exit

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

test_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

echo "=========================================="
echo "  Data Platform Tests"
echo "=========================================="
echo ""

# Test 1: Docker services running
echo "--- Service Health Checks ---"

for service in zookeeper kafka postgres mongodb clickhouse kafka-connect airflow-webserver airflow-scheduler; do
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        test_pass "$service is running"
    else
        test_fail "$service is NOT running"
    fi
done

echo ""
echo "--- Debezium Connectors ---"

# Test 2: Check Debezium connectors
CONNECTORS=$(curl -s http://localhost:8083/connectors 2>/dev/null || echo "[]")

if echo "$CONNECTORS" | grep -q "postgres-users-connector"; then
    test_pass "PostgreSQL connector registered"
else
    test_fail "PostgreSQL connector NOT registered"
fi

if echo "$CONNECTORS" | grep -q "mongodb-events-connector"; then
    test_pass "MongoDB connector registered"
else
    test_fail "MongoDB connector NOT registered"
fi

# Test 3: Check connector status
PG_STATUS=$(curl -s http://localhost:8083/connectors/postgres-users-connector/status 2>/dev/null | grep -o '"state":"RUNNING"' | head -1 || echo "")
if [ -n "$PG_STATUS" ]; then
    test_pass "PostgreSQL connector is RUNNING"
else
    test_fail "PostgreSQL connector is NOT running"
fi

MONGO_STATUS=$(curl -s http://localhost:8083/connectors/mongodb-events-connector/status 2>/dev/null | grep -o '"state":"RUNNING"' | head -1 || echo "")
if [ -n "$MONGO_STATUS" ]; then
    test_pass "MongoDB connector is RUNNING"
else
    test_fail "MongoDB connector is NOT running"
fi

echo ""
echo "--- Kafka Topics ---"

# Test 4: Check Kafka topics exist
TOPICS=$(docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null || echo "")

if echo "$TOPICS" | grep -q "postgres.public.users"; then
    test_pass "Kafka topic 'postgres.public.users' exists"
else
    test_fail "Kafka topic 'postgres.public.users' NOT found"
fi

if echo "$TOPICS" | grep -q "mongo.commerce.events"; then
    test_pass "Kafka topic 'mongo.commerce.events' exists"
else
    test_fail "Kafka topic 'mongo.commerce.events' NOT found"
fi

echo ""
echo "--- ClickHouse Data ---"

# Test 5: Check ClickHouse bronze layer
BRONZE_USERS=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_users" 2>/dev/null || echo "0")
if [ "$BRONZE_USERS" -gt 0 ] 2>/dev/null; then
    test_pass "Bronze users: $BRONZE_USERS rows"
else
    test_fail "Bronze users: 0 rows (CDC not flowing)"
fi

BRONZE_EVENTS=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_events" 2>/dev/null || echo "0")
if [ "$BRONZE_EVENTS" -gt 0 ] 2>/dev/null; then
    test_pass "Bronze events: $BRONZE_EVENTS rows"
else
    test_fail "Bronze events: 0 rows (CDC not flowing)"
fi

# Test 6: Check ClickHouse silver layer
SILVER_USERS=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_users FINAL" 2>/dev/null || echo "0")
if [ "$SILVER_USERS" -gt 0 ] 2>/dev/null; then
    test_pass "Silver users: $SILVER_USERS rows"
else
    test_fail "Silver users: 0 rows"
fi

SILVER_EVENTS=$(curl -s "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_events" 2>/dev/null || echo "0")
if [ "$SILVER_EVENTS" -gt 0 ] 2>/dev/null; then
    test_pass "Silver events: $SILVER_EVENTS rows"
else
    test_fail "Silver events: 0 rows"
fi

echo ""
echo "--- Airflow ---"

# Test 7: Check Airflow health
AIRFLOW_HEALTH=$(curl -s http://localhost:8080/health 2>/dev/null || echo "")
if echo "$AIRFLOW_HEALTH" | grep -q '"status".*"healthy"'; then
    test_pass "Airflow webserver is healthy"
else
    test_fail "Airflow webserver NOT healthy"
fi

# Test 8: Check DAG loaded
DAGS=$(curl -s -u admin:admin http://localhost:8080/api/v1/dags 2>/dev/null || echo "")
if echo "$DAGS" | grep -q "gold_user_activity_daily"; then
    test_pass "DAG 'gold_user_activity_daily' is loaded"
else
    test_fail "DAG 'gold_user_activity_daily' NOT loaded"
fi

echo ""
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Platform is working correctly.${NC}"
else
    echo -e "${YELLOW}Some tests failed. Check the issues above.${NC}"
fi

echo ""
echo "=========================================="
echo "  Sample Queries"
echo "=========================================="
echo ""
echo "View users data:"
echo "  curl 'http://localhost:8123/' --data 'SELECT * FROM analytics.v_silver_users_current LIMIT 5 FORMAT Pretty'"
echo ""
echo "View events data:"
echo "  curl 'http://localhost:8123/' --data 'SELECT user_id, event_type, event_timestamp FROM analytics.silver_events LIMIT 5 FORMAT Pretty'"
echo ""
echo "Trigger Airflow DAG:"
echo "  curl -X POST -u admin:admin http://localhost:8080/api/v1/dags/gold_user_activity_daily/dagRuns -H 'Content-Type: application/json' -d '{\"conf\":{}}'"
