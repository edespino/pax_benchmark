--
-- Phase 6c: Streaming INSERTs - Phase 1 - PROCEDURE TEST (10 batches)
-- Quick validation of PROCEDURE with per-batch commits
-- Runtime: ~2-5 minutes (vs 15-20 minutes for full 500 batches)
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 6c: PROCEDURE TEST'
\echo 'Testing per-batch commits with 10 batches only (NO INDEXES)'
\echo '===================================================='
\echo ''
\echo 'Test parameters:'
\echo '  • Total rows: ~1,000,000 (10 batches, ~100K per batch)'
\echo '  • Total batches: 10 (instead of 500)'
\echo '  • NO INDEXES: Pure INSERT speed'
\echo '  • Transaction model: PER-BATCH commits (10 transactions)'
\echo ''
\echo 'Expected runtime: ~2-5 minutes'
\echo ''

-- =====================================================
-- Create Metrics Tracking Table (Test)
-- =====================================================

\echo 'Creating metrics tracking table (test)...'

DROP TABLE IF EXISTS cdr.streaming_metrics_phase1_test CASCADE;

CREATE TABLE cdr.streaming_metrics_phase1_test (
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
-- Create Helper Function: Generate CDR Data
-- =====================================================

\echo 'Creating CDR data generation function...'

CREATE OR REPLACE FUNCTION cdr.generate_cdr_batch(
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
        'call-' || lpad((p_start_seq + gs)::TEXT, 12, '0') || '-' || substr(md5(random()::TEXT), 1, 8),
        timestamp '2025-10-01 00:00:00' + (p_hour * interval '1 hour') + (gs * interval '3 seconds'),
        DATE '2025-10-01',
        p_hour,
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
        CASE
            WHEN random() < 0.05 THEN (1 + (random() * 9)::INT)::INTEGER
            WHEN random() < 0.85 THEN (30 + (random() * 270)::INT)::INTEGER
            ELSE (300 + (random() * 3300)::INT)::INTEGER
        END,
        (1 + (random() * 9999)::INT)::INTEGER,
        CASE
            WHEN random() < 0.70 THEN 'voice'
            WHEN random() < 0.95 THEN 'sms'
            ELSE 'data'
        END,
        CASE
            WHEN random() < 0.30 THEN '4G'
            WHEN random() < 0.90 THEN '5G'
            ELSE '5G-mmWave'
        END,
        CASE
            WHEN random() < 0.05 THEN (100 + (random() * 10000000)::BIGINT)::BIGINT
            WHEN random() < 0.15 THEN (1 + (random() * 1000)::BIGINT)::BIGINT
            ELSE NULL
        END,
        CASE
            WHEN random() < 0.80 THEN 1
            WHEN random() < 0.90 THEN 16
            WHEN random() < 0.95 THEN 17
            WHEN random() < 0.98 THEN 18
            ELSE (21 + (random() * 106)::INT)::INTEGER
        END,
        (0.10 * CASE
            WHEN random() < 0.05 THEN (1 + (random() * 9)::INT)
            WHEN random() < 0.85 THEN (30 + (random() * 270)::INT)
            ELSE (300 + (random() * 3300)::INT)
        END)::NUMERIC(10,4),
        (1 + (random() * 49)::INT)::INTEGER,
        (random() < 0.10),
        (random() * 4.0 + 1.0)::NUMERIC(3,2),
        (random() * 100)::NUMERIC(5,2),
        p_start_seq + gs
    FROM generate_series(1, p_batch_size) gs;
END;
$$ LANGUAGE plpgsql;

\echo '  ✓ Data generation function created'
\echo ''

-- =====================================================
-- Create Test Procedure (10 batches)
-- =====================================================

\echo 'Creating test procedure (10 batches only)...'

DROP PROCEDURE IF EXISTS cdr.streaming_insert_phase1_test();

CREATE PROCEDURE cdr.streaming_insert_phase1_test()
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_num INTEGER;
    v_batch_size INTEGER := 100000;  -- Fixed 100K per batch for testing
    v_hour INTEGER;
    v_current_seq BIGINT := 0;  -- Start at 0 for Phase 1 test
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration_ms BIGINT;
    v_throughput NUMERIC(12,2);
    v_table_size BIGINT;
BEGIN
    RAISE NOTICE 'Starting 10-batch test (Phase 1 - NO INDEXES)...';
    RAISE NOTICE '';

    -- Test loop: 10 batches
    FOR v_batch_num IN 1..10 LOOP
        v_hour := v_batch_num;  -- Simple hour progression

        RAISE NOTICE '[Batch %/10] Hour: %, Size: % rows, Total: %M',
            v_batch_num, v_hour, v_batch_size, ROUND(v_current_seq / 1000000.0, 1);

        -- AO variant
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_ao
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        v_table_size := pg_total_relation_size('cdr.cdr_ao') / 1024 / 1024;
        INSERT INTO cdr.streaming_metrics_phase1_test VALUES (
            v_batch_num, 'AO', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- AOCO variant
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_aoco
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        v_table_size := pg_total_relation_size('cdr.cdr_aoco') / 1024 / 1024;
        INSERT INTO cdr.streaming_metrics_phase1_test VALUES (
            v_batch_num, 'AOCO', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- PAX variant
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_pax
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        v_table_size := pg_total_relation_size('cdr.cdr_pax') / 1024 / 1024;
        INSERT INTO cdr.streaming_metrics_phase1_test VALUES (
            v_batch_num, 'PAX', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- PAX-no-cluster variant
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_pax_nocluster
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        v_table_size := pg_total_relation_size('cdr.cdr_pax_nocluster') / 1024 / 1024;
        INSERT INTO cdr.streaming_metrics_phase1_test VALUES (
            v_batch_num, 'PAX-no-cluster', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ✅ COMMIT AFTER EACH BATCH
        COMMIT;

        v_current_seq := v_current_seq + v_batch_size;
    END LOOP;

    -- Analyze all tables so queries have statistics
    RAISE NOTICE '';
    RAISE NOTICE 'Analyzing tables to update statistics...';
    ANALYZE cdr.cdr_ao;
    ANALYZE cdr.cdr_aoco;
    ANALYZE cdr.cdr_pax;
    ANALYZE cdr.cdr_pax_nocluster;
    COMMIT;

    RAISE NOTICE '';
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Test complete! 10 batches, 10 commits successful.';
    RAISE NOTICE '==================================================';
END $$;

\echo '  ✓ Test procedure created'
\echo ''

-- =====================================================
-- Execute Test
-- =====================================================

\echo 'Running 10-batch test (Phase 1 - NO INDEXES)...'
\echo ''

CALL cdr.streaming_insert_phase1_test();

\echo ''
\echo 'Test complete! Verifying results...'
\echo ''

-- =====================================================
-- Verify Results
-- =====================================================

\echo 'Test Results:'
\echo '============='
\echo ''

\echo 'Batch count per variant:'
SELECT variant, COUNT(*) as batches
FROM cdr.streaming_metrics_phase1_test
GROUP BY variant
ORDER BY variant;

\echo ''
\echo 'Average throughput per variant:'
SELECT
    variant,
    ROUND(AVG(throughput_rows_sec), 0) AS avg_throughput_rows_sec,
    ROUND(MIN(throughput_rows_sec), 0) AS min_throughput,
    ROUND(MAX(throughput_rows_sec), 0) AS max_throughput
FROM cdr.streaming_metrics_phase1_test
GROUP BY variant
ORDER BY avg_throughput_rows_sec DESC;

\echo ''
\echo 'Total rows inserted (should be 1,000,000 per variant):'
SELECT variant, SUM(rows_inserted) as total_rows
FROM cdr.streaming_metrics_phase1_test
GROUP BY variant
ORDER BY variant;

\echo ''
\echo '===================================================='
\echo 'PHASE 1 PROCEDURE TEST COMPLETE!'
\echo '===================================================='
\echo ''
\echo 'If all counts show 10 batches and 1,000,000 rows:'
\echo '  ✅ PROCEDURE with per-batch commits is working correctly'
\echo '  ✅ Ready for full benchmark'
\echo ''
