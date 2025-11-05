--
-- Phase 7d: Streaming INSERTs - Phase 2 (WITH INDEXES) - WITH HEAP
-- Tests INSERT throughput WITH index maintenance overhead
-- Simulates realistic production scenario with indexes on all tables
--
-- NOTE: This is IDENTICAL to Phase 6 except:
--   1. Tables must have indexes created (via 05_create_indexes.sql)
--   2. Metrics stored in streaming_metrics_phase2 table
--   3. INSERT performance will be slower due to index maintenance
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 7d: Streaming INSERTs (WITH INDEXES)'
\echo '===================================================='
\echo ''
\echo 'Test parameters:'
\echo '  • Total rows: 50,000,000'
\echo '  • Total batches: 500'
\echo '  • Batch sizes: 10K (small), 100K (medium), 500K (large bursts)'
\echo '  • Traffic pattern: Realistic 24-hour telecom simulation'
\echo '  • Variants: AO, AOCO, PAX, PAX-no-cluster, HEAP'
\echo '  • WITH INDEXES: 5 indexes per variant (25 total)'
\echo ''
\echo 'This will take approximately 30-40 minutes (5 variants) (slower than Phase 1)...'
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

    -- Streaming loop (identical to Phase 1, different metrics table)
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

        -- ============================================
        -- INSERT into HEAP variant
        -- ⚠️  Expected: Significant bloat during indexed inserts
        -- ============================================
        v_start_time := clock_timestamp();

        INSERT INTO cdr.cdr_heap
        SELECT * FROM cdr.generate_cdr_batch(v_current_seq, v_batch_size, v_hour);

        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        v_throughput := v_batch_size::NUMERIC / (v_duration_ms::NUMERIC / 1000.0);

        IF v_batch_num % 100 = 0 THEN
            v_table_size := pg_total_relation_size('cdr.cdr_heap') / 1024 / 1024;
        ELSE
            v_table_size := NULL;
        END IF;

        INSERT INTO cdr.streaming_metrics_phase2 VALUES (
            v_batch_num, 'HEAP', v_batch_size, v_start_time, v_end_time,
            v_duration_ms, v_throughput, v_table_size
        );

        -- Checkpoint every 100 batches
        IF v_batch_num % 100 = 0 THEN
            RAISE NOTICE '';
            RAISE NOTICE '====== CHECKPOINT: % batches, %M rows ======',
                v_batch_num, ROUND(v_current_seq / 1000000.0, 1);
            ANALYZE cdr.cdr_ao;
            ANALYZE cdr.cdr_aoco;
            ANALYZE cdr.cdr_pax;
            ANALYZE cdr.cdr_pax_nocluster;
            ANALYZE cdr.cdr_heap;
            RAISE NOTICE 'Tables analyzed (including HEAP)';
            RAISE NOTICE '';
        END IF;

        v_current_seq := v_current_seq + v_batch_size;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Streaming INSERT simulation (Phase 2) complete!';
    RAISE NOTICE 'Total rows inserted: 50,000,000 (per variant)';
    RAISE NOTICE '==================================================';
END $$;

\echo ''
\echo 'Streaming INSERT simulation (Phase 2) complete!'
\echo ''
\echo 'Next: Phase 10 - Collect metrics (compare Phase 1 vs Phase 2)'
