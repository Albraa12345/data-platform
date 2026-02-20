#!/bin/bash

# ===========================================
# Add Event to MongoDB (Interactive)
# ===========================================

echo "=========================================="
echo "  Add New Event"
echo "=========================================="
echo ""
echo "Event types: login, logout, page_view, search, purchase, add_to_cart"
echo ""

read -p "Enter user_id (or press Enter for 1): " USER_ID
read -p "Enter event_type (or press Enter for 'page_view'): " EVENT_TYPE
read -p "Enter metadata key (or press Enter for 'page'): " META_KEY
read -p "Enter metadata value (or press Enter for '/home'): " META_VALUE

# Set defaults if empty
USER_ID=${USER_ID:-1}
EVENT_TYPE=${EVENT_TYPE:-"page_view"}
META_KEY=${META_KEY:-"page"}
META_VALUE=${META_VALUE:-"/home"}
EVENT_ID="evt_$(date +%s%N | cut -c1-13)"

echo ""
echo "Adding event to MongoDB..."
echo "  Event ID: $EVENT_ID"
echo "  User ID: $USER_ID"
echo "  Event Type: $EVENT_TYPE"
echo "  Metadata: {$META_KEY: $META_VALUE}"
echo ""

docker exec mongodb mongosh --quiet --eval "
db = db.getSiblingDB('commerce');
db.events.insertOne({
    event_id: '$EVENT_ID',
    user_id: $USER_ID,
    event_type: '$EVENT_TYPE',
    event_timestamp: new Date(),
    metadata_$META_KEY: '$META_VALUE'
});
print('Event inserted successfully');
"

echo ""
echo "Event added! CDC will sync to ClickHouse automatically."
