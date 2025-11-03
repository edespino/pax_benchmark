--
-- Phase 7a: Streaming INSERTs - Phase 2 (WITH INDEXES) - OPTIMIZED
-- *** TRACK A OPTIMIZATION: Batch cap + ANALYZE tuning + CSV export ***
--
-- Changes from 07_streaming_inserts_withindex.sql:
--   1. BATCH SIZE CAP: Maximum 100K rows per batch (no 500K bursts)
--      - Prevents 30x slowdown observed at batch 380 in production run
--      - Expected impact: 30-40% Phase 2 speedup
--   2. ANALYZE FREQUENCY: Every 250 batches (was every 100)
--      - Reduces ANALYZE operations from 5 to 2 (batch 250, 500)
--      - Expected impact: 5-8% Phase 2 speedup
--   3. CSV EXPORT: Batch-level metrics exported to /tmp/streaming_metrics_phase2.csv
--      - Enables detailed post-run analysis without log parsing
--
-- Tests INSERT throughput WITH index maintenance overhead
-- Simulates realistic production scenario with indexes on all tables
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 7a: Streaming INSERTs (WITH INDEXES) - OPTIMIZED'
\echo '===================================================='
\echo ''
\echo 'Test parameters:'
\echo '  • Total rows: 5,000,000'
\echo '  • Total batches: 50 (TEST VERSION)'
\echo '  • Batch sizes: 10K (small), 100K (medium)'
\echo '  • ⚡ OPTIMIZED: No 500K bursts (capped at 100K)'
\echo '  • ⚡ OPTIMIZED: ANALYZE every 25 batches (TEST: was every 10)'
\echo '  • ⚡ OPTIMIZED: CSV metrics export enabled'
\echo '  • Traffic pattern: Realistic 24-hour telecom simulation'
\echo '  • Variants: AO, AOCO, PAX, PAX-no-cluster'
\echo '  • WITH INDEXES: 5 indexes per variant (20 total)'
\echo ''
\echo 'Expected runtime: 15-20 minutes (vs 5.5 hours baseline)...'
\echo ''

-- =====================================================
-- Create Metrics Tracking Table (Phase 2)
-- =====================================================

\echo 'Creating metrics tracking table (Phase 2)...'

DROP TABLE IF EXISTS cdr.streaming_metrics_phase2 CASCADE;

CREATE TABLE cdr.streaming_metrics_phase2 (
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
-- Verify Indexes Exist
-- =====================================================

\echo 'Verifying indexes exist on all tables...'

DO $$
DECLARE
    v_index_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_index_count
    FROM pg_indexes
    WHERE schemaname = 'cdr'
      AND tablename IN ('cdr_ao', 'cdr_aoco', 'cdr_pax', 'cdr_pax_nocluster');

    IF v_index_count < 20 THEN
        RAISE EXCEPTION 'ERROR: Expected 20 indexes but found %. Run 05_create_indexes.sql first!', v_index_count;
    END IF;

    RAISE NOTICE '  ✓ Found % indexes (expected 20)', v_index_count;
END $$;

\echo ''

-- =====================================================
-- Main Streaming INSERT Loop (WITH INDEX MAINTENANCE)
-- =====================================================

\echo 'Starting streaming INSERT simulation (with index maintenance)...'
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
    v_batch_sizes INTEGER[];
    v_hours INTEGER[];
BEGIN
    -- ==================================================
    -- Generate Traffic Pattern (OPTIMIZED)
    -- ==================================================

    RAISE NOTICE 'Generating realistic 24-hour traffic pattern (OPTIMIZED - no 500K bursts)...';

    v_batch_sizes := ARRAY[]::INTEGER[];
    v_hours := ARRAY[]::INTEGER[];

    FOR v_batch_num IN 1..50 LOOP
        v_hour := ((v_batch_num - 1) * 24 / 500);
        v_hours := array_append(v_hours, v_hour);

        -- *** OPTIMIZATION: Cap batch size at 100K (no 500K bursts) ***
        IF v_hour BETWEEN 0 AND 5 THEN
            v_batch_size := 10000;
        ELSIF v_hour IN (7, 8, 17, 18) THEN
            -- Rush hours: Medium batches only (OPTIMIZED: removed 500K bursts)
            v_batch_size := 100000;  -- All medium (was 70% medium, 30% 500K)
        ELSIF v_hour BETWEEN 9 AND 16 THEN
            IF random() < 0.85 THEN
                v_batch_size := 100000;
            ELSE
                v_batch_size := 10000;
            END IF;
        ELSE
            IF random() < 0.60 THEN
                v_batch_size := 10000;
            ELSE
                v_batch_size := 100000;
            END IF;
        END IF;

        v_batch_sizes := array_append(v_batch_sizes, v_batch_size);
    END LOOP;

    RAISE NOTICE 'Traffic pattern generated: 50 batches, avg size: %',
        (SELECT AVG(unnest) FROM unnest(v_batch_sizes))::INTEGER;
    RAISE NOTICE '';

    -- ==================================================
    -- Streaming INSERT Loop
    -- ==================================================

    FOR v_batch_num IN 1..50 LOOP
        v_batch_size := v_batch_sizes[v_batch_num];
        v_hour := v_hours[v_batch_num];

        IF v_batch_num % 10 = 0 THEN
            RAISE NOTICE '[Batch %/50] Hour: %, Size: % rows, Total: %M',
                v_batch_num, v_hour, v_batch_size, ROUND(v_current_seq / 1000000.0, 1);
        END IF;

        -- ============================================
        -- INSERT into AO variant
        -- ============================================
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_ao
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_ao') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;
        INSERT INTO cdr.streaming_metrics_phase2 VALUES (
            v_batch_num, 'AO', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- INSERT into AOCO variant
        -- ============================================
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_aoco
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_aoco') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;
        INSERT INTO cdr.streaming_metrics_phase2 VALUES (
            v_batch_num, 'AOCO', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- INSERT into PAX variant
        -- ============================================
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_pax
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_pax') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;
        INSERT INTO cdr.streaming_metrics_phase2 VALUES (
            v_batch_num, 'PAX', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- INSERT into PAX-no-cluster variant
        -- ============================================
        v_start_time := clock_timestamp();
        INSERT INTO cdr.cdr_pax_nocluster
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);
        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_pax_nocluster') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;
        INSERT INTO cdr.streaming_metrics_phase2 VALUES (
            v_batch_num, 'PAX-no-cluster', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- ============================================
        -- *** OPTIMIZATION: Checkpoint every 250 batches (was every 100) ***
        -- ============================================
        IF v_batch_num % 25 = 0 THEN
            RAISE NOTICE '';
            RAISE NOTICE '====== CHECKPOINT: % batches, %M rows ======',
                v_batch_num, ROUND(v_current_seq / 1000000.0, 1);
            ANALYZE cdr.cdr_ao;
            ANALYZE cdr.cdr_aoco;
            ANALYZE cdr.cdr_pax;
            ANALYZE cdr.cdr_pax_nocluster;
            RAISE NOTICE 'Tables analyzed (checkpoint)';
            RAISE NOTICE '';
        END IF;

        v_current_seq := v_current_seq + v_batch_size;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Streaming INSERT simulation (Phase 2) complete! (TEST VERSION - 50 batches)';
    RAISE NOTICE 'Total rows inserted: 5,000,000 (per variant)';
    RAISE NOTICE '==================================================';
    RAISE NOTICE '';

    -- ============================================
    -- *** OPTIMIZATION: Export batch-level metrics to CSV ***
    -- ============================================
    RAISE NOTICE 'Exporting batch-level metrics to CSV...';

    -- Note: COPY TO requires superuser or pg_write_server_files role
    -- If this fails, metrics remain in cdr.streaming_metrics_phase2 table
    BEGIN
        EXECUTE $csvexport$
            COPY (
                SELECT
                    variant,
                    batch_num,
                    rows_inserted,
                    duration_ms,
                    throughput_rows_sec,
                    table_size_mb,
                    batch_start_time,
                    batch_end_time
                FROM cdr.streaming_metrics_phase2
                ORDER BY variant, batch_num
            ) TO '/tmp/streaming_metrics_phase2.csv' WITH CSV HEADER
        $csvexport$;

        RAISE NOTICE '  ✓ Metrics exported to /tmp/streaming_metrics_phase2.csv';
        RAISE NOTICE '  ✓ File contains % rows (% batches × 4 variants)',
            (SELECT COUNT(*) FROM cdr.streaming_metrics_phase2),
            (SELECT MAX(batch_num) FROM cdr.streaming_metrics_phase2);
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE '  ⚠ CSV export failed (insufficient privileges)';
            RAISE NOTICE '  ⚠ Metrics still available in cdr.streaming_metrics_phase2 table';
        WHEN OTHERS THEN
            RAISE NOTICE '  ⚠ CSV export failed: %', SQLERRM;
            RAISE NOTICE '  ⚠ Metrics still available in cdr.streaming_metrics_phase2 table';
    END;

    RAISE NOTICE '';
END $$;

\echo ''
\echo 'Streaming INSERT simulation (Phase 2) complete!'
\echo ''
\echo 'Next: Phase 10 - Collect metrics (compare Phase 1 vs Phase 2)'
