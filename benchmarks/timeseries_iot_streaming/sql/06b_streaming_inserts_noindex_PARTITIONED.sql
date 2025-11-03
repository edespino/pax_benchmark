--
-- Phase 6b: Streaming INSERTs - Phase 1 (NO INDEXES) - PARTITIONED
-- *** TRACK B OPTIMIZATION: Table partitioning for smaller index maintenance ***
--
-- Changes from 06a_streaming_inserts_noindex_OPTIMIZED.sql:
--   1. PARTITION ROUTING: call_date = '2024-01-01' + hour (maps hour 0-23 to days 1-24)
--   2. TABLE NAMES: *_partitioned suffix for all variants
--   3. METRICS TABLE: streaming_metrics_phase1_partitioned
--
-- Partitioning Benefits:
--   - 24 partitions × ~1.74M rows each (vs 41.81M monolithic)
--   - Expected Phase 2 speedup: 18-35% (smaller indexes)
--   - Partition pruning: 20-30% query speedup on date-range queries
--
-- Core Innovation: Tests INSERT throughput without index maintenance overhead
-- Simulates realistic telecom/IoT streaming workload:
--   - 500 batches, ~42M total rows
--   - Variable batch sizes (10K small, 100K medium)
--   - Realistic traffic pattern (night/rush-hour/business/evening)
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 6b: Streaming INSERTs (NO INDEXES) - PARTITIONED'
\echo '===================================================='
\echo ''
\echo 'Test parameters:'
\echo '  • Total rows: ~42,000,000 (deterministic with seed=0.5)'
\echo '  • Total batches: 500'
\echo '  • Batch sizes: 10K (small), 100K (medium)'
\echo '  • Partitioning: 24 daily partitions (~1.74M rows/partition)'
\echo '  • Traffic pattern: Realistic 24-hour telecom simulation'
\echo '  • Variants: AO, AOCO, PAX, PAX-no-cluster (all partitioned)'
\echo ''
\echo 'Partition routing strategy:'
\echo '  Hour 0  → 2024-01-01 (partition day00)'
\echo '  Hour 1  → 2024-01-02 (partition day01)'
\echo '  ...'
\echo '  Hour 23 → 2024-01-24 (partition day23)'
\echo ''
\echo 'This will take approximately 15-20 minutes...'
\echo ''

-- =====================================================
-- Create Metrics Tracking Table
-- =====================================================

\echo 'Creating metrics tracking table...'

DROP TABLE IF EXISTS cdr.streaming_metrics_phase1_partitioned CASCADE;

CREATE TABLE cdr.streaming_metrics_phase1_partitioned (
    batch_num INTEGER NOT NULL,
    variant TEXT NOT NULL,
    rows_inserted INTEGER NOT NULL,
    batch_start_time TIMESTAMP NOT NULL,
    batch_end_time TIMESTAMP NOT NULL,
    duration_ms BIGINT NOT NULL,
    throughput_rows_sec NUMERIC(12,2) NOT NULL,
    table_size_mb BIGINT,
    PRIMARY KEY (batch_num, variant)
) DISTRIBUTED BY (batch_num);

\echo '  ✓ Metrics table created'
\echo ''

-- =====================================================
-- Create Helper Function: Generate CDR Data (PARTITIONED)
-- =====================================================

\echo 'Creating CDR data generation function (with partition routing)...'

CREATE OR REPLACE FUNCTION cdr.generate_cdr_batch_partitioned(
    p_start_seq BIGINT,
    p_batch_size INTEGER,
    p_hour INTEGER
) RETURNS TABLE(
    call_id TEXT,
    call_timestamp TIMESTAMP,
    call_date DATE,
    call_hour INTEGER,
    caller_number TEXT,
    callee_number TEXT,
    duration_seconds INTEGER,
    cell_tower_id INTEGER,
    call_type TEXT,
    network_type TEXT,
    bytes_transferred BIGINT,
    termination_code INTEGER,
    billing_amount NUMERIC(10,4),
    rate_plan_id INTEGER,
    is_roaming BOOLEAN,
    call_quality_mos NUMERIC(3,2),
    packet_loss_percent NUMERIC(5,2),
    sequence_number BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        -- Call identifier (HIGH CARDINALITY - unique per call)
        'call-' || lpad((p_start_seq + gs)::TEXT, 12, '0') || '-' || substr(md5(random()::TEXT), 1, 8),

        -- Timestamps (3-second intervals, hour-aware)
        timestamp '2025-10-01 00:00:00' + (p_hour * interval '1 hour') + (gs * interval '3 seconds'),

        -- *** PARTITION ROUTING: Map hour to date for partition ***
        -- Hour 0 → 2024-01-01, Hour 1 → 2024-01-02, ..., Hour 23 → 2024-01-24
        DATE '2024-01-01' + p_hour,

        p_hour,

        -- Phone numbers (Zipf distribution)
        '+1-' || lpad(
            CASE
                WHEN random() < 0.2 THEN (1 + (random() * 199999)::INT)::TEXT
                WHEN random() < 0.6 THEN (200000 + (random() * 799999)::INT)::TEXT
                ELSE (1000000 + (random() * 4000000)::INT)::TEXT
            END, 10, '0'),
        '+1-' || lpad(
            CASE
                WHEN random() < 0.2 THEN (1 + (random() * 199999)::INT)::TEXT
                WHEN random() < 0.6 THEN (200000 + (random() * 799999)::INT)::TEXT
                ELSE (1000000 + (random() * 4000000)::INT)::TEXT
            END, 10, '0'),

        -- Call duration
        CASE
            WHEN random() < 0.05 THEN (1 + (random() * 9)::INT)::INTEGER
            WHEN random() < 0.85 THEN (30 + (random() * 270)::INT)::INTEGER
            ELSE (300 + (random() * 3300)::INT)::INTEGER
        END,

        -- Cell tower
        (1 + (random() * 9999)::INT)::INTEGER,

        -- Call type
        CASE
            WHEN random() < 0.70 THEN 'voice'
            WHEN random() < 0.95 THEN 'sms'
            ELSE 'data'
        END,

        -- Network type
        CASE
            WHEN random() < 0.30 THEN '4G'
            WHEN random() < 0.90 THEN '5G'
            ELSE '5G-mmWave'
        END,

        -- Data transferred (sparse)
        CASE
            WHEN random() < 0.05 THEN (100 + (random() * 10000000)::BIGINT)::BIGINT
            WHEN random() < 0.15 THEN (1 + (random() * 1000)::BIGINT)::BIGINT
            ELSE NULL
        END,

        -- Termination reason
        CASE
            WHEN random() < 0.80 THEN 1
            WHEN random() < 0.90 THEN 16
            WHEN random() < 0.95 THEN 17
            WHEN random() < 0.98 THEN 18
            ELSE (21 + (random() * 106)::INT)::INTEGER
        END,

        -- Billing amount
        (0.10 * CASE
            WHEN random() < 0.05 THEN (1 + (random() * 9)::INT)
            WHEN random() < 0.85 THEN (30 + (random() * 270)::INT)
            ELSE (300 + (random() * 3300)::INT)
        END)::NUMERIC(10,4),

        -- Rate plan
        (1 + (random() * 49)::INT)::INTEGER,

        -- Roaming
        (random() < 0.10),

        -- Quality metrics
        (random() * 4.0 + 1.0)::NUMERIC(3,2),
        (random() * 100)::NUMERIC(5,2),

        -- Sequence
        p_start_seq + gs
    FROM generate_series(1, p_batch_size) gs;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ Data generation function created (with partition routing)'
\echo ''

-- =====================================================
-- Main Streaming INSERT Loop
-- =====================================================

\echo 'Starting streaming INSERT simulation (partitioned tables)...'
\echo ''

DO $$
DECLARE
    v_batch_num INTEGER;
    v_batch_size INTEGER;
    v_hour INTEGER;
    v_current_seq BIGINT := 0;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration_ms BIGINT;
    v_throughput NUMERIC(12,2);
    v_table_size BIGINT;

    -- Traffic pattern arrays (500 batches)
    v_batch_sizes INTEGER[];
    v_hours INTEGER[];
BEGIN
    -- ==================================================
    -- Set Deterministic Seed for Reproducibility
    -- ==================================================

    -- Use fixed seed to make batch sizes deterministic across runs
    PERFORM setseed(0.5);

    -- ==================================================
    -- Generate Traffic Pattern (OPTIMIZED)
    -- ==================================================

    RAISE NOTICE 'Generating realistic 24-hour traffic pattern (OPTIMIZED - no 500K bursts)...';
    RAISE NOTICE 'Using deterministic seed (0.5) for reproducible batch sizes';
    RAISE NOTICE 'Partition routing: Hour % → 2024-01-% (24 partitions)', 0, '01', 01;

    -- Initialize arrays
    v_batch_sizes := ARRAY[]::INTEGER[];
    v_hours := ARRAY[]::INTEGER[];

    FOR v_batch_num IN 1..500 LOOP
        -- Determine hour of day (cycle through 24 hours, 20.8 batches per hour)
        v_hour := ((v_batch_num - 1) * 24 / 500);
        v_hours := array_append(v_hours, v_hour);

        -- *** OPTIMIZATION: Cap batch size at 100K (no 500K bursts) ***
        IF v_hour BETWEEN 0 AND 5 THEN
            -- Night (00:00-06:00): Small batches only
            v_batch_size := 10000;
        ELSIF v_hour IN (7, 8, 17, 18) THEN
            -- Rush hours: Medium batches only (OPTIMIZED: removed 500K bursts)
            v_batch_size := 100000;  -- All medium (was 70% medium, 30% 500K)
        ELSIF v_hour BETWEEN 9 AND 16 THEN
            -- Business hours: Mostly medium
            IF random() < 0.85 THEN
                v_batch_size := 100000;  -- 85% medium
            ELSE
                v_batch_size := 10000;   -- 15% small
            END IF;
        ELSE
            -- Evening (19:00-23:00): Mix of small/medium
            IF random() < 0.60 THEN
                v_batch_size := 10000;   -- 60% small
            ELSE
                v_batch_size := 100000;  -- 40% medium
            END IF;
        END IF;

        v_batch_sizes := array_append(v_batch_sizes, v_batch_size);
    END LOOP;

    RAISE NOTICE 'Traffic pattern generated: 500 batches, avg size: %',
        (SELECT AVG(unnest) FROM unnest(v_batch_sizes))::INTEGER;
    RAISE NOTICE '';

    -- ==================================================
    -- Streaming INSERT Loop
    -- ==================================================

    FOR v_batch_num IN 1..500 LOOP
        v_batch_size := v_batch_sizes[v_batch_num];
        v_hour := v_hours[v_batch_num];

        -- Progress indicator every 10 batches
        IF v_batch_num % 10 = 0 THEN
            RAISE NOTICE '[Batch %/500] Hour: %, Partition: 2024-01-%, Size: % rows, Total: %M',
                v_batch_num, v_hour, lpad((v_hour + 1)::TEXT, 2, '0'), v_batch_size, ROUND(v_current_seq / 1000000.0, 1);
        END IF;

        -- ============================================
        -- INSERT into AO partitioned variant
        -- ============================================
        v_start_time := clock_timestamp();

        INSERT INTO cdr.cdr_ao_partitioned
        SELECT * FROM cdr.generate_cdr_batch_partitioned(v_current_seq, v_batch_size, v_hour);

        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);

        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_ao_partitioned') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;

        INSERT INTO cdr.streaming_metrics_phase1_partitioned VALUES (
            v_batch_num, 'AO', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- INSERT into AOCO partitioned variant
        -- ============================================
        v_start_time := clock_timestamp();

        INSERT INTO cdr.cdr_aoco_partitioned
        SELECT * FROM cdr.generate_cdr_batch_partitioned(v_current_seq, v_batch_size, v_hour);

        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);

        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_aoco_partitioned') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;

        INSERT INTO cdr.streaming_metrics_phase1_partitioned VALUES (
            v_batch_num, 'AOCO', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- INSERT into PAX partitioned variant
        -- ============================================
        v_start_time := clock_timestamp();

        INSERT INTO cdr.cdr_pax_partitioned
        SELECT * FROM cdr.generate_cdr_batch_partitioned(v_current_seq, v_batch_size, v_hour);

        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);

        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_pax_partitioned') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;

        INSERT INTO cdr.streaming_metrics_phase1_partitioned VALUES (
            v_batch_num, 'PAX', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- INSERT into PAX-no-cluster partitioned variant
        -- ============================================
        v_start_time := clock_timestamp();

        INSERT INTO cdr.cdr_pax_nocluster_partitioned
        SELECT * FROM cdr.generate_cdr_batch_partitioned(v_current_seq, v_batch_size, v_hour);

        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);

        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_pax_nocluster_partitioned') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;

        INSERT INTO cdr.streaming_metrics_phase1_partitioned VALUES (
            v_batch_num, 'PAX-no-cluster', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- Checkpoint every 100 batches (~8.4M rows)
        -- ============================================
        IF v_batch_num % 100 = 0 THEN
            RAISE NOTICE '';
            RAISE NOTICE '====== CHECKPOINT: % batches complete, %M rows total ======',
                v_batch_num, ROUND(v_current_seq / 1000000.0, 1);

            -- ANALYZE partitioned tables (analyzes all partitions)
            ANALYZE cdr.cdr_ao_partitioned;
            ANALYZE cdr.cdr_aoco_partitioned;
            ANALYZE cdr.cdr_pax_partitioned;
            ANALYZE cdr.cdr_pax_nocluster_partitioned;

            RAISE NOTICE 'Partitioned tables analyzed';
            RAISE NOTICE '';
        END IF;

        v_current_seq := v_current_seq + v_batch_size;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Streaming INSERT simulation complete (partitioned)!';
    RAISE NOTICE 'Total rows inserted: % (per variant)', v_current_seq;
    RAISE NOTICE 'Rows per partition: ~%', ROUND(v_current_seq / 24.0, 0);
    RAISE NOTICE '==================================================';
END $$;

\echo ''
\echo 'Streaming INSERT simulation complete!'
\echo ''
\echo 'Final ANALYZE on all partitioned tables...'

ANALYZE cdr.cdr_ao_partitioned;
ANALYZE cdr.cdr_aoco_partitioned;
ANALYZE cdr.cdr_pax_partitioned;
ANALYZE cdr.cdr_pax_nocluster_partitioned;

\echo '  ✓ Analysis complete'
\echo ''
\echo 'Next: Phase 8 - Collect metrics OR Phase 5b - Create indexes (for Phase 2)'
