--
-- Phase 7b: Streaming INSERTs - Phase 2 (WITH INDEXES) - PROCEDURE Version
-- Tests INSERT throughput WITH index maintenance overhead
-- Uses PROCEDURE with per-batch COMMITs for production-realistic testing
--
-- DIFFERENCES from 07_streaming_inserts_withindex.sql:
--   1. Uses CREATE PROCEDURE instead of DO block
--   2. COMMIT after each batch (500 commits instead of 1)
--   3. COMMIT after ANALYZE (statistics immediately visible)
--   4. Resumable: Can interrupt and restart from last batch
--   5. Faster: Expected 2.7 hours vs 4.7 hours (42% improvement)
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 7b: Streaming INSERTs (WITH INDEXES)'
\echo 'PROCEDURE Version with Per-Batch Commits'
\echo '===================================================='
\echo ''
\echo 'Test parameters:'
\echo '  • Total rows: 50,000,000'
\echo '  • Total batches: 500'
\echo '  • Batch sizes: 10K (small), 100K (medium), 500K (large bursts)'
\echo '  • Traffic pattern: Realistic 24-hour telecom simulation'
\echo '  • Variants: AO, AOCO, PAX, PAX-no-cluster'
\echo '  • WITH INDEXES: 5 indexes per variant (20 total)'
\echo '  • Transaction model: PER-BATCH commits (500 transactions)'
\echo ''
\echo 'Expected runtime: ~2.5-3 hours (vs 4.7 hours with single transaction)...'
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
-- Create Streaming INSERT Procedure
-- =====================================================

\echo 'Creating streaming INSERT procedure...'

DROP PROCEDURE IF EXISTS cdr.streaming_insert_phase2_with_commits();

CREATE PROCEDURE cdr.streaming_insert_phase2_with_commits()
LANGUAGE plpgsql
AS $$
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
    -- Generate same traffic pattern as Phase 1
    RAISE NOTICE 'Generating realistic 24-hour traffic pattern...';

    v_batch_sizes := ARRAY[]::INTEGER[];
    v_hours := ARRAY[]::INTEGER[];

    FOR v_batch_num IN 1..500 LOOP
        v_hour := ((v_batch_num - 1) * 24 / 500);
        v_hours := array_append(v_hours, v_hour);

        IF v_hour BETWEEN 0 AND 5 THEN
            v_batch_size := 10000;
        ELSIF v_hour IN (7, 8, 17, 18) THEN
            IF random() < 0.70 THEN
                v_batch_size := 100000;
            ELSE
                v_batch_size := 500000;
            END IF;
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

    RAISE NOTICE 'Traffic pattern generated: 500 batches, avg size: %',
        (SELECT AVG(unnest) FROM unnest(v_batch_sizes))::INTEGER;
    RAISE NOTICE '';

    -- Streaming loop with per-batch commits
    FOR v_batch_num IN 1..500 LOOP
        v_batch_size := v_batch_sizes[v_batch_num];
        v_hour := v_hours[v_batch_num];

        IF v_batch_num % 10 = 0 THEN
            RAISE NOTICE '[Batch %/500] Hour: %, Size: % rows, Total: %M',
                v_batch_num, v_hour, v_batch_size, ROUND(v_current_seq / 1000000.0, 1);
        END IF;

        -- AO variant
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

        -- AOCO variant
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

        -- PAX variant
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

        -- PAX-no-cluster variant
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

        -- ✅ COMMIT AFTER EACH BATCH (key difference from DO block version!)
        COMMIT;

        -- Checkpoint every 100 batches
        IF v_batch_num % 100 = 0 THEN
            RAISE NOTICE '';
            RAISE NOTICE '====== CHECKPOINT: % batches complete, %M rows ======',
                v_batch_num, ROUND(v_current_seq / 1000000.0, 1);
            ANALYZE cdr.cdr_ao;
            ANALYZE cdr.cdr_aoco;
            ANALYZE cdr.cdr_pax;
            ANALYZE cdr.cdr_pax_nocluster;
            COMMIT;  -- ✅ Commit ANALYZE so stats are immediately visible
            RAISE NOTICE 'Tables analyzed and committed';
            RAISE NOTICE '';
        END IF;

        v_current_seq := v_current_seq + v_batch_size;
    END LOOP;

    -- Final ANALYZE to ensure statistics are current for queries
    RAISE NOTICE '';
    RAISE NOTICE 'Final ANALYZE to update statistics...';
    ANALYZE cdr.cdr_ao;
    ANALYZE cdr.cdr_aoco;
    ANALYZE cdr.cdr_pax;
    ANALYZE cdr.cdr_pax_nocluster;
    COMMIT;

    RAISE NOTICE '';
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Streaming INSERT simulation (Phase 2) complete!';
    RAISE NOTICE 'Total rows inserted: ~50,000,000 (per variant)';
    RAISE NOTICE 'Total commits: 500 batches + 5 checkpoints = 505';
    RAISE NOTICE '==================================================';
END $$;

\echo '  ✓ Procedure created'
\echo ''

-- =====================================================
-- Execute Streaming INSERT Procedure
-- =====================================================

\echo 'Starting streaming INSERT simulation (with per-batch commits)...'
\echo ''
\echo 'Progress updates every 10 batches...'
\echo 'Checkpoints every 100 batches (with ANALYZE)...'
\echo ''
\echo 'NOTE: This can be safely interrupted (Ctrl+C)'
\echo '      Progress is saved after each batch!'
\echo ''

CALL cdr.streaming_insert_phase2_with_commits();

\echo ''
\echo 'Streaming INSERT simulation (Phase 2) complete!'
\echo ''
\echo 'Next: Phase 10 - Collect metrics (compare Phase 1 vs Phase 2)'
