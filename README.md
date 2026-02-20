# Real-Time Data Platform with CDC, Kafka, ClickHouse & Airflow

A production-grade, fault-tolerant, scalable data platform implementing real-time Change Data Capture (CDC) with batch analytics capabilities.

---

## Quick Start Guide

### Prerequisites

- **Docker Desktop** with WSL 2 backend enabled
- **WSL 2** (Ubuntu recommended)
- At least **8GB RAM** allocated to Docker

### 1. WSL Setup (Windows)

```bash
# Install WSL if not already installed
wsl --install -d Ubuntu

# Open WSL terminal
wsl

# Navigate to project directory
cd /mnt/c/Users/<your-username>/barakah-code-challenge
```

### 2. Start the Platform

```bash
# Fix MongoDB keyfile permissions (required for auth)
chmod 400 mongodb/keyfile

# Make startup script executable
chmod +x startup.sh

# Start all services
./startup.sh
```

Or start manually:
```bash
docker-compose up -d
```

### 3. Verify Services Are Running

```bash
docker-compose ps
```

All services should show `Up (healthy)`.

### 4. Add Test Data

**Add a new user (PostgreSQL):**
```bash
chmod +x scripts/add_user.sh
./scripts/add_user.sh
# Follow prompts to enter email and name
```

**Add a new event (MongoDB):**
```bash
chmod +x scripts/add_event.sh
./scripts/add_event.sh
# Follow prompts to enter user_id, event_type, and metadata
```

**Add sample data (both):**
```bash
chmod +x scripts/add_sample_data.sh
./scripts/add_sample_data.sh
```

### 5. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airflow UI** | http://localhost:8080 | admin / admin |
| **Kafka UI** | http://localhost:8081 | - |
| **ClickHouse HTTP** | http://localhost:8123 | - |

> **Note (WSL):** If `localhost` doesn't work, get WSL IP: `hostname -I | awk '{print $1}'`

---

## Working with ClickHouse

### Connect to ClickHouse

```bash
# Via Docker
docker exec -it clickhouse clickhouse-client

# Or via HTTP API
curl 'http://localhost:8123/'
```

### View Available Tables

```sql
-- List all tables in analytics database
SHOW TABLES FROM analytics;

-- Describe table structure
DESCRIBE TABLE analytics.bronze_users;
DESCRIBE TABLE analytics.bronze_events;
DESCRIBE TABLE analytics.silver_users;
DESCRIBE TABLE analytics.silver_events;
DESCRIBE TABLE analytics.gold_user_activity;
```

### Query Data (Examples)

**Bronze Layer (Raw CDC Data):**
```sql
-- View recent users from CDC
SELECT * FROM analytics.bronze_users ORDER BY _ingested_at DESC LIMIT 10;

-- View recent events from CDC
SELECT * FROM analytics.bronze_events ORDER BY _ingested_at DESC LIMIT 10;

-- Count records
SELECT count() FROM analytics.bronze_users;
SELECT count() FROM analytics.bronze_events;
```

**Silver Layer (Cleaned Data):**
```sql
-- Current state of users (deduplicated)
SELECT * FROM analytics.v_silver_users_current LIMIT 10;

-- Events with parsed timestamps
SELECT user_id, event_type, event_timestamp 
FROM analytics.silver_events 
ORDER BY event_timestamp DESC LIMIT 10;
```

**Gold Layer (Aggregated Analytics):**
```sql
-- Daily user activity summary
SELECT * FROM analytics.gold_user_activity 
ORDER BY activity_date DESC LIMIT 10;

-- User activity metrics
SELECT 
    user_id,
    activity_date,
    total_events,
    distinct_event_types
FROM analytics.gold_user_activity
WHERE activity_date = today();
```

### HTTP API Queries

```bash
# Count users
curl 'http://localhost:8123/' --data 'SELECT count() FROM analytics.bronze_users'

# Get recent events (formatted)
curl 'http://localhost:8123/' --data 'SELECT * FROM analytics.bronze_events ORDER BY _ingested_at DESC LIMIT 5 FORMAT Pretty'

# Export as JSON
curl 'http://localhost:8123/' --data 'SELECT * FROM analytics.silver_users FINAL LIMIT 10 FORMAT JSON'
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              DATA PLATFORM ARCHITECTURE                             │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐     ┌──────────────────┐
│   PostgreSQL    │     │    MongoDB       │
│   (commerce)    │     │   (commerce)     │
│                 │     │                  │
│  ┌───────────┐  │     │  ┌────────────┐  │
│  │   users   │  │     │  │  events    │  │
│  │  (table)  │  │     │  │(collection)│  │
│  └───────────┘  │     │  └────────────┘  │
│        │        │     │        │         │
│   WAL (logical) │     │  Change Stream   │
└────────┼────────┘     └────────┼─────────┘
         │                       │
         ▼                       ▼
┌─────────────────────────────────────────┐
│           DEBEZIUM (CDC Engine)         │
│  ┌─────────────────┐ ┌────────────────┐ │
│  │ PG Connector    │ │ Mongo Connector│ │
│  └─────────────────┘ └────────────────┘ │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│              APACHE KAFKA               │
│  ┌─────────────────────────────────────┐│
│  │ postgres.public.users               ││
│  │ mongo.commerce.events               ││
│  └─────────────────────────────────────┘│
│              (Zookeeper)                │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    CLICKHOUSE                                       │
│  ┌────────────────────────────────────────────────────────────────────────────────┐ │
│  │                            BRONZE LAYER (Raw)                                  │ │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐                    │ │
│  │  │ bronze_users_kafka      │    │ bronze_events_kafka     │  ← Kafka Engine    │ │
│  │  │ (Kafka Engine)          │    │ (Kafka Engine)          │                    │ │
│  │  └───────────┬─────────────┘    └───────────┬─────────────┘                    │ │
│  │              │ MV                           │ MV                               │ │
│  │              ▼                              ▼                                  │ │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐                    │ │
│  │  │ bronze_users            │    │ bronze_events           │  ← MergeTree       │ │
│  │  │ (persistent)            │    │ (persistent)            │                    │ │
│  │  └───────────┬─────────────┘    └───────────┬─────────────┘                    │ │
│  └──────────────┼──────────────────────────────┼──────────────────────────────────┘ │
│                 │                              │                                    │
│  ┌──────────────┼──────────────────────────────┼──────────────────────────────────┐ │
│  │              │     SILVER LAYER (Cleaned)   │                                  │ │
│  │              ▼                              ▼                                  │ │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐                    │ │
│  │  │ silver_users            │    │ silver_events           │                    │ │
│  │  │ (ReplacingMergeTree)    │    │ (MergeTree)             │                    │ │
│  │  │ • Current state only    │    │ • Append-only           │                    │ │
│  │  │ • Soft deletes          │    │ • Partitioned by date   │                    │ │
│  │  │ • Version-based dedup   │    │ • Indexed for queries   │                    │ │
│  │  └───────────┬─────────────┘    └───────────┬─────────────┘                    │ │
│  └──────────────┼──────────────────────────────┼──────────────────────────────────┘ │
│                 │                              │                                    │
│  ┌──────────────┼──────────────────────────────┼──────────────────────────────────┐ │
│  │              │      GOLD LAYER (Analytics)  │                                  │ │
│  │              └──────────────┬───────────────┘                                  │ │
│  │                             ▼                                                  │ │
│  │              ┌─────────────────────────────┐                                   │ │
│  │              │ gold_user_activity          │  ← Airflow DAG (daily)            │ │
│  │              │ (ReplacingMergeTree)        │                                   │ │
│  │              │ • Daily aggregations        │                                   │ │
│  │              │ • User + Event join         │                                   │ │
│  │              │ • Idempotent refresh        │                                   │ │
│  │              └─────────────────────────────┘                                   │ │
│  └────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              APACHE AIRFLOW                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │  gold_user_activity_daily DAG                                                     │  │
│  │  ┌─────────┐   ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐           │  │
│  │  │Validate │ → │Delete   │ → │Compute   │ → │Optimize  │ → │Validate  │ → Report  │  │
│  │  │Source   │   │Partition│   │Aggregates│   │Table     │   │Results   │           │  │
│  │  └─────────┘   └─────────┘   └──────────┘   └──────────┘   └──────────┘           │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| **PostgreSQL** | Source database with users table (CDC enabled) | 5432 |
| **MongoDB** | Source database with events collection (CDC enabled) | 27017 |
| **Zookeeper** | Kafka cluster coordination | 2181 |
| **Kafka** | Message broker for CDC events | 9092, 29092 |
| **Kafka Connect (Debezium)** | CDC connector platform | 8083 |
| **ClickHouse** | Analytics data warehouse (medallion architecture) | 8123, 9000 |
| **Airflow** | Workflow orchestration for batch processing | 8080 |
| **Kafka UI** | Kafka monitoring dashboard | 8081 |

## Quick Start

### Prerequisites

- Docker Desktop 4.x+
- Docker Compose v2.x+
- 16GB+ RAM recommended
- 20GB+ free disk space

### 1. Clone and Setup

```powershell
# Clone repository
git clone <repository-url>
cd barakah-code-challenge

# Set environment variables
$env:AIRFLOW_UID = 50000
```

### 2. Start the Platform

**Option A: Using PowerShell Script (Recommended for Windows)**

```powershell
.\init-scripts\setup.ps1
```

**Option B: Manual Step-by-Step**

```bash
# Start infrastructure
docker-compose up -d zookeeper
sleep 10
docker-compose up -d kafka
sleep 15

# Start source databases
docker-compose up -d postgres mongodb
sleep 10
docker-compose up -d mongodb-init
sleep 15

# Start Kafka Connect
docker-compose up -d kafka-connect
sleep 30

# Start ClickHouse
docker-compose up -d clickhouse
sleep 15

# Start Airflow
docker-compose up -d airflow-postgres
sleep 10
docker-compose up -d airflow-init
sleep 30
docker-compose up -d airflow-webserver airflow-scheduler

# Start monitoring
docker-compose up -d kafka-ui
```

### 3. Initialize ClickHouse Schema

The ClickHouse init scripts run automatically, but you can manually run them:

```bash
# Execute schema files
for f in clickhouse/init/*.sql; do
  curl -s "http://localhost:8123/" --data-binary @"$f"
done
```

### 4. Register Debezium Connectors

```bash
# PostgreSQL connector
curl -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/postgres-connector.json \
  http://localhost:8083/connectors

# MongoDB connector  
curl -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/mongodb-connector.json \
  http://localhost:8083/connectors
```

### 5. Verify the Pipeline

```bash
# Check connector status
curl http://localhost:8083/connectors?expand=status

# Check ClickHouse data
curl "http://localhost:8123/" --data "SELECT count() FROM analytics.bronze_users"
curl "http://localhost:8123/" --data "SELECT count() FROM analytics.silver_events"
```

### 6. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Airflow UI | http://localhost:8080 | admin / admin |
| Kafka UI | http://localhost:8081 | - |
| ClickHouse HTTP | http://localhost:8123 | default / (empty) |
| Kafka Connect REST | http://localhost:8083 | - |

---

## How CDC Works

### PostgreSQL CDC (Logical Replication)

```
┌──────────────────────────────────────────────────────────────┐
│                     PostgreSQL CDC Flow                       │
└──────────────────────────────────────────────────────────────┘

  Application                PostgreSQL                 Debezium
      │                          │                          │
      │  INSERT/UPDATE/DELETE    │                          │
      ├─────────────────────────►│                          │
      │                          │                          │
      │                    ┌─────┴─────┐                    │
      │                    │  WAL Log  │                    │
      │                    │ (logical) │                    │
      │                    └─────┬─────┘                    │
      │                          │                          │
      │                          │  Replication Slot        │
      │                          ├─────────────────────────►│
      │                          │                          │
      │                          │                    ┌─────┴─────┐
      │                          │                    │  Debezium │
      │                          │                    │ Connector │
      │                          │                    └─────┬─────┘
      │                          │                          │
      │                          │                          │  CDC Event
      │                          │                          ├──────────►
      │                          │                          │  to Kafka
```

**Key Configuration:**
- `wal_level=logical` enables logical decoding
- `REPLICA IDENTITY FULL` captures full row data for updates/deletes
- Debezium uses `pgoutput` plugin for native logical replication
- Replication slot ensures no data loss during connector restarts

### MongoDB CDC (Change Streams)

```
┌──────────────────────────────────────────────────────────────┐
│                     MongoDB CDC Flow                          │
└──────────────────────────────────────────────────────────────┘

  Application                 MongoDB                   Debezium
      │                          │                          │
      │  Insert/Update/Delete    │                          │
      ├─────────────────────────►│                          │
      │                          │                          │
      │                    ┌─────┴─────┐                    │
      │                    │  Oplog    │                    │
      │                    │ (rs0)     │                    │
      │                    └─────┬─────┘                    │
      │                          │                          │
      │                          │  Change Stream           │
      │                          ├─────────────────────────►│
      │                          │                          │
      │                          │                    ┌─────┴─────┐
      │                          │                    │  Debezium │
      │                          │                    │ Connector │
      │                          │                    └─────┬─────┘
      │                          │                          │
      │                          │                          │  CDC Event
      │                          │                          ├──────────►
      │                          │                          │  to Kafka
```

**Key Configuration:**
- MongoDB runs as replica set (`rs0`) for oplog availability
- Change Streams API provides reliable event ordering
- `capture.mode=change_streams_update_full` captures full documents

### CDC Message Format

After Debezium's `ExtractNewRecordState` transformation:

```json
{
  "user_id": 1,
  "full_name": "Alice Johnson",
  "email": "alice@example.com",
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:00Z",
  "__op": "c",           // c=create, u=update, d=delete, r=read(snapshot)
  "__ts_ms": 1705312200000,
  "__source_ts_ms": 1705312199000,
  "__deleted": "false"   // "true" for delete operations
}
```

---

## How Idempotency is Ensured

### 1. Bronze Layer (Kafka Ingestion)

- **Kafka Consumer Offsets**: ClickHouse Kafka engine commits offsets after successful processing
- **Automatic Recovery**: On restart, consumption resumes from last committed offset
- **Skip Broken Messages**: Configured to skip malformed messages without blocking

### 2. Silver Layer (ReplacingMergeTree)

```sql
ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id)
```

- **Version-based Deduplication**: Higher `_version` wins during merge
- **FINAL Keyword**: Guarantees deduplicated results at query time
- **CDC Ordering**: `_version` derived from source timestamp maintains correct ordering

### 3. Gold Layer (Airflow DAG)

```
┌─────────────────────────────────────────────────────────────┐
│           Idempotent Batch Processing Pattern                │
└─────────────────────────────────────────────────────────────┘

  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │   Validate   │────►│    Delete    │────►│   Compute    │
  │  Source Data │     │  Partition   │     │ Aggregations │
  └──────────────┘     └──────────────┘     └──────────────┘
         │                    │                    │
         │                    │                    │
         ▼                    ▼                    ▼
   Check data exists   Remove existing      INSERT...SELECT
   for target date     rows for date        fresh aggregations
                       (ALTER DELETE)
```

**Idempotency Guarantees:**
1. **Delete-before-insert**: Old data removed before new data inserted
2. **Partition-aware**: Only affects target date partition
3. **Atomic operations**: ClickHouse transactions ensure consistency
4. **ReplacingMergeTree**: Even duplicate inserts are deduplicated by version

### 4. Backfill Safety

```python
# Airflow DAG configuration
DAG_CONFIG = {
    'catchup': True,        # Process historical dates
    'max_active_runs': 1,   # Prevent concurrent runs
}
```

- **Sequential Execution**: Only one DAG run at a time prevents race conditions
- **Date-based Partitioning**: Each run operates on isolated partition
- **Re-runnable**: Any historical date can be reprocessed safely

---

## Failure Recovery Strategy

### 1. Kafka Connect Failures

| Failure | Recovery |
|---------|----------|
| Connector crash | Auto-restart with offset tracking |
| Database unavailable | Exponential backoff retry |
| Kafka unavailable | Buffer in memory, retry with backoff |
| Schema change | Requires connector reconfiguration |

**Commands:**
```bash
# Check connector status
curl http://localhost:8083/connectors/postgres-users-connector/status

# Restart failed connector
curl -X POST http://localhost:8083/connectors/postgres-users-connector/restart

# Reset offsets (danger: may cause duplicates)
curl -X DELETE http://localhost:8083/connectors/postgres-users-connector
# Re-create connector with snapshot.mode=schema_only to skip initial load
```

### 2. ClickHouse Failures

| Failure | Recovery |
|---------|----------|
| Kafka consumer lag | Automatically catches up on restart |
| Out of memory | Reduce batch size, add more RAM |
| Disk full | Add storage, configure TTL |
| Table corruption | Restore from replica or backup |

**Commands:**
```bash
# Check Kafka consumer lag
curl "http://localhost:8123/" --data "
  SELECT * FROM system.kafka_consumers 
  WHERE database = 'analytics'
"

# Force table optimization
curl "http://localhost:8123/" --data "
  OPTIMIZE TABLE analytics.silver_users FINAL
"

# Check mutations
curl "http://localhost:8123/" --data "
  SELECT * FROM system.mutations 
  WHERE is_done = 0
"
```

### 3. Airflow DAG Failures

| Failure | Recovery |
|---------|----------|
| Task failure | Automatic retry (3x with backoff) |
| ClickHouse unavailable | Retry with exponential backoff |
| Data validation failure | Manual investigation required |
| Timeout | Increase `execution_timeout` |

**Commands:**
```bash
# Clear failed task for re-run
airflow tasks clear gold_user_activity_daily -t compute_aggregations -s 2024-01-15 -e 2024-01-15

# Backfill historical dates
airflow dags backfill gold_user_activity_daily -s 2024-01-01 -e 2024-01-31

# Trigger manual run
airflow dags trigger gold_user_activity_daily --exec-date 2024-01-15
```

### 4. Full System Recovery

```bash
# 1. Stop all services
docker-compose down

# 2. Start infrastructure
docker-compose up -d zookeeper kafka postgres mongodb

# 3. Wait for databases
sleep 30

# 4. Start CDC layer
docker-compose up -d kafka-connect clickhouse

# 5. Re-register connectors (if needed)
curl -X POST -H "Content-Type: application/json" \
  --data @debezium/connectors/postgres-connector.json \
  http://localhost:8083/connectors

# 6. Start orchestration
docker-compose up -d airflow-webserver airflow-scheduler

# 7. Backfill any missed data
airflow dags backfill gold_user_activity_daily \
  -s $(date -d "7 days ago" +%Y-%m-%d) \
  -e $(date +%Y-%m-%d)
```

---

## Scaling Considerations

### Horizontal Scaling

| Component | Scaling Strategy |
|-----------|------------------|
| **Kafka** | Add brokers, increase partitions |
| **Kafka Connect** | Increase `tasks.max`, add workers |
| **ClickHouse** | Add shards for write scaling, replicas for read scaling |
| **Airflow** | Switch to CeleryExecutor or KubernetesExecutor |

### Kafka Scaling

```yaml
# Increase partitions for parallel processing
kafka-topics --alter --topic postgres.public.users \
  --partitions 6 --bootstrap-server kafka:29092

# Connector parallelism
{
  "tasks.max": "3",  # One task per partition
}
```

### ClickHouse Scaling

```sql
-- Add replica for high availability
CREATE TABLE analytics.silver_users_replica AS analytics.silver_users
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/silver_users', '{replica}', _version)

-- Distributed table for sharding
CREATE TABLE analytics.silver_users_distributed AS analytics.silver_users
ENGINE = Distributed(cluster_name, analytics, silver_users, user_id)
```

### Resource Recommendations

| Scale | Users | Events/day | Infrastructure |
|-------|-------|------------|----------------|
| Small | <100K | <1M | Single node, 16GB RAM |
| Medium | <1M | <10M | 3-node Kafka, 2-node CH |
| Large | <10M | <100M | 5-node Kafka cluster, 4-shard CH |
| Enterprise | 10M+ | 100M+ | Dedicated clusters, K8s |

---

## Project Structure

```
barakah-code-challenge/
├── docker-compose.yml           # Complete service definitions
├── .env                         # Environment variables
├── .gitignore                   # Git ignore rules
├── README.md                    # This documentation
│
├── postgres/
│   └── init/
│       ├── 01_init_schema.sql   # Users table, replication config
│       └── 02_sample_operations.sql  # Sample CDC operations
│
├── mongodb/
│   ├── keyfile                  # Replica set authentication
│   └── init/
│       └── 01_init_events.js    # Events collection, sample data
│
├── debezium/
│   └── connectors/
│       ├── postgres-connector.json   # PostgreSQL CDC config
│       └── mongodb-connector.json    # MongoDB CDC config
│
├── clickhouse/
│   ├── config/
│   │   ├── config.xml           # Server configuration
│   │   └── users.xml            # User profiles & quotas
│   └── init/
│       ├── 01_create_database.sql    # Database creation
│       ├── 02_bronze_layer.sql       # Kafka engine tables
│       ├── 03_silver_layer.sql       # Transformed tables
│       └── 04_gold_layer.sql         # Aggregated tables
│
├── airflow/
│   ├── dags/
│   │   ├── __init__.py
│   │   └── gold_user_activity_daily.py  # Production DAG
│   ├── logs/
│   ├── plugins/
│   └── config/
│
└── init-scripts/
    ├── setup.ps1                # Windows setup script
    ├── 01_setup_connectors.sh   # Connector registration
    ├── 02_init_clickhouse.sh    # Schema initialization
    ├── 03_generate_test_data.sh # Test data generation
    └── 04_verify_pipeline.sh    # Pipeline verification
```

---

## Troubleshooting

### Common Issues

**1. Kafka Connect fails to start**
```bash
# Check logs
docker-compose logs kafka-connect

# Ensure Kafka is healthy
docker-compose exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092
```

**2. MongoDB connector fails**
```bash
# Verify replica set
docker-compose exec mongodb mongosh --eval "rs.status()"

# Check debezium user permissions
docker-compose exec mongodb mongosh -u admin -p admin --eval "
  use commerce;
  db.getUser('debezium');
"
```

**3. ClickHouse not receiving data**
```bash
# Check Kafka topics have data
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres.public.users \
  --from-beginning --max-messages 5

# Check Kafka engine errors
curl "http://localhost:8123/" --data "
  SELECT * FROM system.kafka_consumers
  WHERE database = 'analytics'
"
```

**4. Airflow DAG not running**
```bash
# Check DAG is parsed
docker-compose exec airflow-scheduler airflow dags list

# Check for import errors
docker-compose exec airflow-scheduler python /opt/airflow/dags/gold_user_activity_daily.py
```

---

## Monitoring

### Key Metrics to Watch

| Metric | Location | Alert Threshold |
|--------|----------|-----------------|
| Kafka consumer lag | Kafka UI | > 10,000 messages |
| Connector status | Kafka Connect API | state != RUNNING |
| ClickHouse query latency | system.query_log | > 30 seconds |
| Airflow task failures | Airflow UI | > 2 consecutive |
| Disk usage | All services | > 80% |

### Useful Queries

```sql
-- ClickHouse: Data freshness
SELECT 
  table,
  max(event_time) as latest_data,
  now() - max(event_time) as lag
FROM system.parts
WHERE database = 'analytics'
GROUP BY table;

-- ClickHouse: Table sizes
SELECT 
  table,
  formatReadableSize(sum(bytes)) as size,
  sum(rows) as rows
FROM system.parts
WHERE database = 'analytics' AND active
GROUP BY table
ORDER BY sum(bytes) DESC;
```

---

## License

This project is provided as a technical demonstration. Use at your own discretion.

---

## Support

For issues and questions:
1. Check the Troubleshooting section
2. Review service logs: `docker-compose logs [service-name]`
3. Verify all services are healthy: `docker-compose ps`
