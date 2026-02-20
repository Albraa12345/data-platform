#!/bin/bash

# ===========================================
# Add User to PostgreSQL (Interactive)
# ===========================================

echo "=========================================="
echo "  Add New User"
echo "=========================================="
echo ""

read -p "Enter email (or press Enter for random): " EMAIL
read -p "Enter full name (or press Enter for 'Test User'): " FULL_NAME

# Set defaults if empty
EMAIL=${EMAIL:-"user$(date +%s)@example.com"}
FULL_NAME=${FULL_NAME:-"Test User"}

echo ""
echo "Adding user to PostgreSQL..."
echo "  Email: $EMAIL"
echo "  Full Name: $FULL_NAME"
echo ""

docker exec -i postgres psql -U postgres -d commerce -c "
INSERT INTO users (email, full_name)
VALUES ('$EMAIL', '$FULL_NAME')
RETURNING user_id, email, full_name, created_at;
"

echo ""
echo "User added! CDC will sync to ClickHouse automatically."
