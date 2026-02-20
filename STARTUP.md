# Data Platform Startup Guide

## Prerequisites

- Docker Desktop with WSL2 integration enabled
- WSL2 (Ubuntu recommended)
- At least 8GB RAM available for Docker

---

## Quick Start (One Command)

Open WSL terminal and run:

```bash
cd /data-platform
chmod +x startup.sh
./startup.sh
```

---

## Manual Startup Steps

### Step 1: Navigate to Project

```bash
cd /data-platform
```

### Step 2: Start Core Infrastructure

```bash
docker-compose up -d zookeeper kafka postgres mongodb
sleep 15
```

### Step 3: Initialize MongoDB Replica Set

```bash
docker-compose up -d mongodb-init
sleep 15
```

### Step 4: Start Kafka Connect & ClickHouse

```bash
docker-compose up -d kafka-connect clickhouse kafka-ui
sleep 30
```

### Step 5: Initialize Airflow

```bash
docker-compose up -d airflow-postgres
sleep 10
docker-compose up -d airflow-init
sleep 45
docker-compose up -d airflow-webserver airflow-scheduler
sleep 30
```

### Step 6: Register Debezium Connectors

```bash
# PostgreSQL Connector
curl -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/postgres-connector.json \
  http://localhost:8083/connectors

# MongoDB Connector
curl -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/mongodb-connector.json \
  http://localhost:8083/connectors
```

### Step 7: Insert Test Data (Optional)

```bash
# Insert MongoDB events
docker exec -i mongodb mongosh < init-scripts/insert_mongo_events.js
```

---

## Verify Services

```bash
docker-compose ps
```

Expected output - all services should show `Up (healthy)`:

| Service | Port | Status |
|---------|------|--------|
| airflow-webserver | 8080 | healthy |
| airflow-scheduler | - | healthy |
| clickhouse | 8123, 9000 | healthy |
| kafka | 9092, 29092 | healthy |
| kafka-connect | 8083 | healthy |
| mongodb | 27017 | healthy |
| postgres | 5432 | healthy |
| zookeeper | 2181 | healthy |

---

## Access URLs

Get WSL IP address:

```bash
hostname -I | awk '{print $1}'
```

Then access services at:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airflow UI** | http://[WSL_IP]:8080 | admin / admin |
| **Kafka UI** | http://[WSL_IP]:8081 | - |
| **ClickHouse HTTP** | http://[WSL_IP]:8123 | default / (empty) |
| **Kafka Connect REST** | http://[WSL_IP]:8083 | - |

---

## Verify Data Pipeline

```bash
# Check connectors
curl http://localhost:8083/connectors

# Check ClickHouse data
curl "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_users"
curl "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_events"
curl "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_users FINAL"
curl "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_events"
```

---

## Stop All Services

```bash
docker-compose down
```

## Stop and Remove Volumes (Clean Restart)

```bash
docker-compose down -v
```

---

## Troubleshooting

### Airflow not accessible from Windows browser

Use WSL IP instead of localhost:

```bash
WSL_IP=$(hostname -I | awk '{print $1}')
echo "Access Airflow at: http://${WSL_IP}:8080"
```

### ClickHouse unhealthy

Restart with fresh volume:

```bash
docker-compose stop clickhouse
docker-compose rm -f clickhouse
docker volume rm data-platform_clickhouse_data
docker-compose up -d clickhouse
```

### MongoDB init failed

Restart MongoDB services:

```bash
docker-compose stop mongodb mongodb-init
docker-compose rm -f mongodb mongodb-init
docker volume rm data-platform_mongodb_data
docker-compose up -d mongodb
sleep 15
docker-compose up -d mongodb-init
```

### Airflow DB not initialized

Re-run initialization:

```bash
docker-compose stop airflow-webserver airflow-scheduler
docker-compose rm -f airflow-init
docker-compose up -d airflow-init
sleep 45
docker-compose up -d airflow-webserver airflow-scheduler
```
