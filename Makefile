# ============================================
# Data Platform Makefile
# ============================================
# Convenience commands for managing the platform

.PHONY: help start stop restart status logs clean init connectors verify health

SHELL := /bin/bash

# Default target
help:
	@echo "Data Platform Management Commands"
	@echo "=================================="
	@echo ""
	@echo "Infrastructure:"
	@echo "  make start      - Start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make status     - Show service status"
	@echo "  make logs       - Tail all logs"
	@echo "  make clean      - Stop services and remove volumes"
	@echo ""
	@echo "Initialization:"
	@echo "  make init       - Initialize ClickHouse schema"
	@echo "  make connectors - Register Debezium connectors"
	@echo ""
	@echo "Verification:"
	@echo "  make verify     - Verify data pipeline"
	@echo "  make health     - Run health check"
	@echo ""
	@echo "Individual Services:"
	@echo "  make kafka-logs     - Tail Kafka logs"
	@echo "  make connect-logs   - Tail Kafka Connect logs"
	@echo "  make clickhouse-logs- Tail ClickHouse logs"
	@echo "  make airflow-logs   - Tail Airflow logs"

# Start all services
start:
	@echo "Starting data platform..."
	docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 30
	@echo "Platform started. Run 'make status' to check service health."

# Stop all services
stop:
	@echo "Stopping data platform..."
	docker-compose down

# Restart all services
restart: stop start

# Show service status
status:
	docker-compose ps

# Tail all logs
logs:
	docker-compose logs -f

# Clean up everything
clean:
	@echo "WARNING: This will delete all data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker-compose down -v; \
		echo "Cleaned up."; \
	fi

# Initialize ClickHouse schema
init:
	@echo "Initializing ClickHouse schema..."
	@for f in clickhouse/init/*.sql; do \
		echo "Executing: $$f"; \
		curl -s "http://localhost:8123/" --data-binary @"$$f"; \
	done
	@echo "Schema initialized."

# Register Debezium connectors
connectors:
	@echo "Registering Debezium connectors..."
	@echo "PostgreSQL connector..."
	@curl -s -X POST -H "Content-Type: application/json" \
		--data @debezium/connectors/postgres-connector.json \
		http://localhost:8083/connectors || true
	@sleep 5
	@echo "MongoDB connector..."
	@curl -s -X POST -H "Content-Type: application/json" \
		--data @debezium/connectors/mongodb-connector.json \
		http://localhost:8083/connectors || true
	@echo "Connectors registered."

# Verify pipeline
verify:
	@./init-scripts/04_verify_pipeline.sh

# Health check
health:
	@./init-scripts/05_health_check.sh

# Individual service logs
kafka-logs:
	docker-compose logs -f kafka

connect-logs:
	docker-compose logs -f kafka-connect

clickhouse-logs:
	docker-compose logs -f clickhouse

airflow-logs:
	docker-compose logs -f airflow-webserver airflow-scheduler
