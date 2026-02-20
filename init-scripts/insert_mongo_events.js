db = db.getSiblingDB('commerce');

db.events.insertMany([{
        event_id: 'evt_001',
        user_id: 1,
        event_type: 'login',
        event_timestamp: new Date(),
        metadata: {
            device: 'mobile',
            os: 'iOS'
        }
    },
    {
        event_id: 'evt_002',
        user_id: 1,
        event_type: 'page_view',
        event_timestamp: new Date(),
        metadata: {
            page: '/home',
            device: 'mobile'
        }
    },
    {
        event_id: 'evt_003',
        user_id: 2,
        event_type: 'purchase',
        event_timestamp: new Date(),
        metadata: {
            total: 99.99,
            product_id: 'prod_123'
        }
    },
    {
        event_id: 'evt_004',
        user_id: 3,
        event_type: 'search',
        event_timestamp: new Date(),
        metadata: {
            query: 'laptop',
            results: 25
        }
    },
    {
        event_id: 'evt_005',
        user_id: 2,
        event_type: 'add_to_cart',
        event_timestamp: new Date(),
        metadata: {
            product_id: 'prod_456',
            quantity: 2
        }
    }
]);

print('Inserted ' + db.events.countDocuments({}) + ' events');