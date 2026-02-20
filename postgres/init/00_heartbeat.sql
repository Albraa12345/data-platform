-- ============================================
-- Debezium Heartbeat Table
-- ============================================
-- Used by Debezium connector for health monitoring

CREATE TABLE IF NOT EXISTS public.debezium_heartbeat (
    id INTEGER PRIMARY KEY,
    ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial row
INSERT INTO public.debezium_heartbeat (id, ts) VALUES (1, NOW())
ON CONFLICT (id) DO UPDATE SET ts = NOW();

-- Grant permissions
GRANT ALL ON public.debezium_heartbeat TO postgres;
