#!/bin/bash

# ===========================================
# Add Sample Data to Sources
# Adds multiple users and events for testing
# ===========================================

echo "=========================================="
echo "  Adding Sample Data"
echo "=========================================="

# Add users to PostgreSQL
echo ""
echo "--- Adding Users to PostgreSQL ---"

docker exec -i postgres psql -U postgres -d commerce -c "
INSERT INTO users (email, full_name) VALUES
('alice@example.com', 'Alice Johnson'),
('bob@example.com', 'Bob Smith'),
('charlie@example.com', 'Charlie Brown')
ON CONFLICT (email) DO UPDATE SET updated_at = NOW()
RETURNING user_id, email, full_name;
"

# Add events to MongoDB
echo ""
echo "--- Adding Events to MongoDB ---"

docker exec mongodb mongosh --quiet --eval "
db = db.getSiblingDB('commerce');

var events = [
    { event_id: 'evt_' + Date.now() + '_1', user_id: 1, event_type: 'login', event_timestamp: new Date(), metadata_device: 'desktop', metadata_os: 'Windows' },
    { event_id: 'evt_' + Date.now() + '_2', user_id: 1, event_type: 'page_view', event_timestamp: new Date(), metadata_page: '/dashboard' },
    { event_id: 'evt_' + Date.now() + '_3', user_id: 2, event_type: 'purchase', event_timestamp: new Date(), metadata_total: 149.99, metadata_product_id: 'prod_abc' },
    { event_id: 'evt_' + Date.now() + '_4', user_id: 2, event_type: 'search', event_timestamp: new Date(), metadata_query: 'laptop' },
    { event_id: 'evt_' + Date.now() + '_5', user_id: 3, event_type: 'logout', event_timestamp: new Date(), metadata_device: 'mobile' }
];

db.events.insertMany(events);
print('Inserted ' + events.length + ' events');
"

echo ""
echo "=========================================="
echo "  Data Added Successfully!"
echo "=========================================="
echo ""
echo "Wait a few seconds for CDC to sync, then verify:"
echo ""
echo "Users in ClickHouse:"
echo "  curl 'http://localhost:8123/' --data 'SELECT count() FROM analytics.bronze_users'"
echo ""
echo "Events in ClickHouse:"
echo "  curl 'http://localhost:8123/' --data 'SELECT count() FROM analytics.bronze_events'"
