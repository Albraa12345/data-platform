#!/bin/bash
# ============================================
# Test Data Generation Script
# ============================================
# Generates additional CDC events for testing

set -e

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-commerce}"

MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"

echo "============================================"
echo "Generating Test CDC Events"
echo "============================================"

# Function to execute PostgreSQL commands
psql_exec() {
    PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "$1"
}

# Generate PostgreSQL CDC events
echo ""
echo "Generating PostgreSQL CDC events..."

# Insert new users
psql_exec "INSERT INTO users (full_name, email) VALUES 
    ('Test User $(date +%s)', 'test.user.$(date +%s)@example.com');"

# Update existing users
psql_exec "UPDATE users SET full_name = full_name || ' (updated)' WHERE user_id = 1;"

echo "PostgreSQL events generated."

# Generate MongoDB CDC events
echo ""
echo "Generating MongoDB CDC events..."

mongosh --host "${MONGO_HOST}:${MONGO_PORT}" \
    -u admin -p admin \
    --authenticationDatabase admin \
    --eval "
        use commerce;
        
        // Insert new events
        db.events.insertMany([
            {
                event_id: 'evt_test_' + new Date().getTime(),
                user_id: 1,
                event_type: 'page_view',
                event_timestamp: new Date(),
                metadata: {
                    page: '/test-page',
                    device: 'desktop',
                    test: true
                }
            },
            {
                event_id: 'evt_test_' + (new Date().getTime() + 1),
                user_id: 2,
                event_type: 'purchase',
                event_timestamp: new Date(),
                metadata: {
                    order_id: 'ord_test_' + new Date().getTime(),
                    total: 99.99,
                    test: true
                }
            }
        ]);
        
        print('MongoDB events generated');
    "

echo ""
echo "============================================"
echo "Test Data Generation Complete!"
echo "============================================"
echo ""
echo "Check Kafka topics for new CDC messages:"
echo "  - postgres.public.users"
echo "  - mongo.commerce.events"
