// ============================================
// MongoDB Initialization Script
// Commerce Database - Events Collection
// ============================================

// Switch to commerce database
db = db.getSiblingDB('commerce');

// Create events collection with schema validation
db.createCollection('events', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['event_id', 'user_id', 'event_type', 'event_timestamp'],
            properties: {
                event_id: {
                    bsonType: 'string',
                    description: 'Unique event identifier - required'
                },
                user_id: {
                    bsonType: 'int',
                    description: 'Reference to user - required'
                },
                event_type: {
                    bsonType: 'string',
                    enum: ['page_view', 'click', 'purchase', 'add_to_cart', 'remove_from_cart', 'search', 'login', 'logout', 'signup'],
                    description: 'Type of event - required'
                },
                event_timestamp: {
                    bsonType: 'date',
                    description: 'When the event occurred - required'
                },
                metadata: {
                    bsonType: 'object',
                    description: 'Additional event data'
                }
            }
        }
    },
    validationLevel: 'moderate',
    validationAction: 'warn'
});

// Create indexes for efficient querying
db.events.createIndex({
    'event_id': 1
}, {
    unique: true
});
db.events.createIndex({
    'user_id': 1
});
db.events.createIndex({
    'event_type': 1
});
db.events.createIndex({
    'event_timestamp': -1
});
db.events.createIndex({
    'user_id': 1,
    'event_timestamp': -1
});

// ============================================
// Insert Sample Events
// ============================================

const sampleEvents = [
    // User 1 - Alice's journey
    {
        event_id: 'evt_001',
        user_id: 1,
        event_type: 'login',
        event_timestamp: new Date('2024-01-15T10:30:00Z'),
        metadata: {
            device: 'mobile',
            os: 'iOS',
            browser: 'Safari'
        }
    },
    {
        event_id: 'evt_002',
        user_id: 1,
        event_type: 'page_view',
        event_timestamp: new Date('2024-01-15T10:31:00Z'),
        metadata: {
            page: '/products',
            category: 'electronics'
        }
    },
    {
        event_id: 'evt_003',
        user_id: 1,
        event_type: 'search',
        event_timestamp: new Date('2024-01-15T10:32:00Z'),
        metadata: {
            query: 'wireless headphones',
            results_count: 45
        }
    },
    {
        event_id: 'evt_004',
        user_id: 1,
        event_type: 'click',
        event_timestamp: new Date('2024-01-15T10:33:00Z'),
        metadata: {
            element: 'product_card',
            product_id: 'prod_123'
        }
    },
    {
        event_id: 'evt_005',
        user_id: 1,
        event_type: 'add_to_cart',
        event_timestamp: new Date('2024-01-15T10:35:00Z'),
        metadata: {
            product_id: 'prod_123',
            quantity: 1,
            price: 79.99
        }
    },
    {
        event_id: 'evt_006',
        user_id: 1,
        event_type: 'purchase',
        event_timestamp: new Date('2024-01-15T10:40:00Z'),
        metadata: {
            order_id: 'ord_001',
            total: 87.99,
            items: 1,
            payment_method: 'credit_card'
        }
    },

    // User 2 - Bob's journey
    {
        event_id: 'evt_007',
        user_id: 2,
        event_type: 'login',
        event_timestamp: new Date('2024-01-16T14:45:00Z'),
        metadata: {
            device: 'desktop',
            os: 'Windows',
            browser: 'Chrome'
        }
    },
    {
        event_id: 'evt_008',
        user_id: 2,
        event_type: 'page_view',
        event_timestamp: new Date('2024-01-16T14:46:00Z'),
        metadata: {
            page: '/deals',
            category: 'all'
        }
    },
    {
        event_id: 'evt_009',
        user_id: 2,
        event_type: 'add_to_cart',
        event_timestamp: new Date('2024-01-16T14:50:00Z'),
        metadata: {
            product_id: 'prod_456',
            quantity: 2,
            price: 29.99
        }
    },
    {
        event_id: 'evt_010',
        user_id: 2,
        event_type: 'remove_from_cart',
        event_timestamp: new Date('2024-01-16T14:52:00Z'),
        metadata: {
            product_id: 'prod_456',
            quantity: 1
        }
    },
    {
        event_id: 'evt_011',
        user_id: 2,
        event_type: 'purchase',
        event_timestamp: new Date('2024-01-16T15:00:00Z'),
        metadata: {
            order_id: 'ord_002',
            total: 32.99,
            items: 1,
            payment_method: 'paypal'
        }
    },
    {
        event_id: 'evt_012',
        user_id: 2,
        event_type: 'logout',
        event_timestamp: new Date('2024-01-16T15:05:00Z'),
        metadata: {
            session_duration_minutes: 20
        }
    },

    // User 3 - Carol's journey
    {
        event_id: 'evt_013',
        user_id: 3,
        event_type: 'signup',
        event_timestamp: new Date('2024-01-17T09:15:00Z'),
        metadata: {
            referrer: 'google',
            campaign: 'winter_sale'
        }
    },
    {
        event_id: 'evt_014',
        user_id: 3,
        event_type: 'page_view',
        event_timestamp: new Date('2024-01-17T09:16:00Z'),
        metadata: {
            page: '/welcome',
            first_visit: true
        }
    },
    {
        event_id: 'evt_015',
        user_id: 3,
        event_type: 'search',
        event_timestamp: new Date('2024-01-17T09:20:00Z'),
        metadata: {
            query: 'winter jacket',
            results_count: 120
        }
    },

    // User 4 - David's journey
    {
        event_id: 'evt_016',
        user_id: 4,
        event_type: 'login',
        event_timestamp: new Date('2024-01-18T16:20:00Z'),
        metadata: {
            device: 'tablet',
            os: 'Android',
            browser: 'Chrome'
        }
    },
    {
        event_id: 'evt_017',
        user_id: 4,
        event_type: 'page_view',
        event_timestamp: new Date('2024-01-18T16:21:00Z'),
        metadata: {
            page: '/account/orders'
        }
    },
    {
        event_id: 'evt_018',
        user_id: 4,
        event_type: 'click',
        event_timestamp: new Date('2024-01-18T16:22:00Z'),
        metadata: {
            element: 'track_order',
            order_id: 'ord_003'
        }
    },

    // User 5 - Emma's journey
    {
        event_id: 'evt_019',
        user_id: 5,
        event_type: 'login',
        event_timestamp: new Date('2024-01-19T11:00:00Z'),
        metadata: {
            device: 'mobile',
            os: 'Android',
            browser: 'Firefox'
        }
    },
    {
        event_id: 'evt_020',
        user_id: 5,
        event_type: 'page_view',
        event_timestamp: new Date('2024-01-19T11:01:00Z'),
        metadata: {
            page: '/products/clothing'
        }
    },
    {
        event_id: 'evt_021',
        user_id: 5,
        event_type: 'add_to_cart',
        event_timestamp: new Date('2024-01-19T11:10:00Z'),
        metadata: {
            product_id: 'prod_789',
            quantity: 3,
            price: 19.99
        }
    },
    {
        event_id: 'evt_022',
        user_id: 5,
        event_type: 'add_to_cart',
        event_timestamp: new Date('2024-01-19T11:12:00Z'),
        metadata: {
            product_id: 'prod_790',
            quantity: 1,
            price: 49.99
        }
    },
    {
        event_id: 'evt_023',
        user_id: 5,
        event_type: 'purchase',
        event_timestamp: new Date('2024-01-19T11:20:00Z'),
        metadata: {
            order_id: 'ord_004',
            total: 119.96,
            items: 4,
            payment_method: 'credit_card'
        }
    },

    // Additional events for users 6-10
    {
        event_id: 'evt_024',
        user_id: 6,
        event_type: 'login',
        event_timestamp: new Date('2024-01-20T08:30:00Z'),
        metadata: {
            device: 'desktop',
            os: 'macOS',
            browser: 'Safari'
        }
    },
    {
        event_id: 'evt_025',
        user_id: 6,
        event_type: 'page_view',
        event_timestamp: new Date('2024-01-20T08:31:00Z'),
        metadata: {
            page: '/products/sports'
        }
    },
    {
        event_id: 'evt_026',
        user_id: 7,
        event_type: 'login',
        event_timestamp: new Date('2024-01-21T13:45:00Z'),
        metadata: {
            device: 'mobile',
            os: 'iOS',
            browser: 'Safari'
        }
    },
    {
        event_id: 'evt_027',
        user_id: 7,
        event_type: 'search',
        event_timestamp: new Date('2024-01-21T13:46:00Z'),
        metadata: {
            query: 'running shoes',
            results_count: 89
        }
    },
    {
        event_id: 'evt_028',
        user_id: 8,
        event_type: 'login',
        event_timestamp: new Date('2024-01-22T15:10:00Z'),
        metadata: {
            device: 'desktop',
            os: 'Linux',
            browser: 'Firefox'
        }
    },
    {
        event_id: 'evt_029',
        user_id: 8,
        event_type: 'purchase',
        event_timestamp: new Date('2024-01-22T15:30:00Z'),
        metadata: {
            order_id: 'ord_005',
            total: 249.99,
            items: 1,
            payment_method: 'credit_card'
        }
    },
    {
        event_id: 'evt_030',
        user_id: 9,
        event_type: 'signup',
        event_timestamp: new Date('2024-01-23T10:00:00Z'),
        metadata: {
            referrer: 'facebook',
            campaign: 'new_year'
        }
    }
];

// Insert all sample events
db.events.insertMany(sampleEvents);

// Log initialization success
print('MongoDB commerce database initialized successfully');
print('Events collection created with ' + db.events.countDocuments() + ' sample events');
print('Indexes created: ' + db.events.getIndexes().length);