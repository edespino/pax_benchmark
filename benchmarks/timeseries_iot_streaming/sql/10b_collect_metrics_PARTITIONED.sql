--
-- Phase 10b: Collect Comprehensive Metrics (PARTITIONED VARIANTS)
-- Analyzes streaming INSERT performance and storage efficiency for partitioned tables
-- Compares Phase 1 (no indexes) vs Phase 2 (with indexes) if available
--
-- Partitioned tables: cdr.cdr_*_partitioned (24 partitions each)
-- Note: pg_total_relation_size() on parent returns 0 (expected Greenplum/Cloudberry behavior)
--       We use pg_partition_tree() to sum leaf partition sizes
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 10b: Collect Metrics (PARTITIONED)'
\echo '===================================================='
\echo ''

-- =====================================================
-- Section 1: Storage Comparison
-- =====================================================

\echo 'Section 1: Storage Comparison (Partitioned Variants)'
\echo '====================================================='
\echo ''

SELECT
    variant_name,
    pg_size_pretty(table_size) AS size,
    ROUND((table_size::NUMERIC / aoco_size::NUMERIC), 2) AS vs_aoco_ratio,
    CASE
        WHEN table_size = MIN(table_size) OVER () THEN '🏆 Smallest'
        WHEN table_size < aoco_size * 1.1 THEN '✅ Excellent (<10% overhead)'
        WHEN table_size < aoco_size * 1.3 THEN '🟠 Acceptable (<30% overhead)'
        ELSE '❌ High overhead (>30%)'
    END AS assessment
FROM (
    SELECT
        'AO' AS variant_name,
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_ao_partitioned')
         WHERE isleaf = true) AS table_size,
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_aoco_partitioned')
         WHERE isleaf = true) AS aoco_size
    UNION ALL
    SELECT
        'AOCO',
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_aoco_partitioned')
         WHERE isleaf = true),
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_aoco_partitioned')
         WHERE isleaf = true)
    UNION ALL
    SELECT
        'PAX',
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_pax_partitioned')
         WHERE isleaf = true),
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_aoco_partitioned')
         WHERE isleaf = true)
    UNION ALL
    SELECT
        'PAX-no-cluster',
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_pax_nocluster_partitioned')
         WHERE isleaf = true),
        (SELECT SUM(pg_total_relation_size(relid))
         FROM pg_partition_tree('cdr.cdr_aoco_partitioned')
         WHERE isleaf = true)
) sizes
ORDER BY table_size;

\echo ''

-- =====================================================
-- Section 2: Compression Effectiveness
-- =====================================================

\echo 'Section 2: Compression Effectiveness'
\echo '====================================='
\echo ''

-- Estimate raw size based on row count and average row width
-- Note: pg_total_relation_size() on parent returns 0, use pg_partition_tree()
-- Note: Avoid UNION ALL with COUNT(*) on distributed tables (MPP limitation)
DO $$
DECLARE
    v_ao_count BIGINT;
    v_ao_size BIGINT;
    v_aoco_count BIGINT;
    v_aoco_size BIGINT;
    v_pax_count BIGINT;
    v_pax_size BIGINT;
    v_pax_nc_count BIGINT;
    v_pax_nc_size BIGINT;
    v_raw_estimate BIGINT := 200; -- bytes per CDR row
BEGIN
    -- Get row counts
    SELECT COUNT(*) INTO v_ao_count FROM cdr.cdr_ao_partitioned;
    SELECT COUNT(*) INTO v_aoco_count FROM cdr.cdr_aoco_partitioned;
    SELECT COUNT(*) INTO v_pax_count FROM cdr.cdr_pax_partitioned;
    SELECT COUNT(*) INTO v_pax_nc_count FROM cdr.cdr_pax_nocluster_partitioned;

    -- Get sizes using pg_partition_tree()
    SELECT SUM(pg_total_relation_size(relid)) INTO v_ao_size
    FROM pg_partition_tree('cdr.cdr_ao_partitioned') WHERE isleaf = true;

    SELECT SUM(pg_total_relation_size(relid)) INTO v_aoco_size
    FROM pg_partition_tree('cdr.cdr_aoco_partitioned') WHERE isleaf = true;

    SELECT SUM(pg_total_relation_size(relid)) INTO v_pax_size
    FROM pg_partition_tree('cdr.cdr_pax_partitioned') WHERE isleaf = true;

    SELECT SUM(pg_total_relation_size(relid)) INTO v_pax_nc_size
    FROM pg_partition_tree('cdr.cdr_pax_nocluster_partitioned') WHERE isleaf = true;

    -- Display results
    RAISE NOTICE 'Compression analysis (partitioned variants):';
    RAISE NOTICE '';
    RAISE NOTICE 'AO: % rows, compressed: %, estimated raw: %, ratio: %x',
        v_ao_count,
        pg_size_pretty(v_ao_size),
        pg_size_pretty(v_ao_count * v_raw_estimate),
        ROUND((v_ao_count * v_raw_estimate)::NUMERIC / v_ao_size::NUMERIC, 2);

    RAISE NOTICE 'AOCO: % rows, compressed: %, estimated raw: %, ratio: %x',
        v_aoco_count,
        pg_size_pretty(v_aoco_size),
        pg_size_pretty(v_aoco_count * v_raw_estimate),
        ROUND((v_aoco_count * v_raw_estimate)::NUMERIC / v_aoco_size::NUMERIC, 2);

    RAISE NOTICE 'PAX: % rows, compressed: %, estimated raw: %, ratio: %x',
        v_pax_count,
        pg_size_pretty(v_pax_size),
        pg_size_pretty(v_pax_count * v_raw_estimate),
        ROUND((v_pax_count * v_raw_estimate)::NUMERIC / v_pax_size::NUMERIC, 2);

    RAISE NOTICE 'PAX-no-cluster: % rows, compressed: %, estimated raw: %, ratio: %x',
        v_pax_nc_count,
        pg_size_pretty(v_pax_nc_size),
        pg_size_pretty(v_pax_nc_count * v_raw_estimate),
        ROUND((v_pax_nc_count * v_raw_estimate)::NUMERIC / v_pax_nc_size::NUMERIC, 2);
END $$;

\echo ''

-- =====================================================
-- Section 3: Phase 1 INSERT Performance (No Indexes)
-- =====================================================

\echo 'Section 3: Phase 1 INSERT Performance (No Indexes, Partitioned)'
\echo '================================================================'
\echo ''

-- Detect and use correct Phase 1 table name (production or test, partitioned)
DO $$
DECLARE
    v_table_name TEXT;
    v_query TEXT;
    v_result RECORD;
BEGIN
    -- Check which table exists (partitioned variants)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_partitioned_test') THEN
        v_table_name := 'streaming_metrics_phase1_partitioned_test';
        RAISE NOTICE 'Phase 1 metrics found (PARTITIONED TEST run) - analyzing...';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_partitioned') THEN
        v_table_name := 'streaming_metrics_phase1_partitioned';
        RAISE NOTICE 'Phase 1 metrics found (PARTITIONED PRODUCTION run) - analyzing...';
    ELSE
        RAISE NOTICE 'Phase 1 metrics not found (partitioned table does not exist)';
        RAISE NOTICE 'Run 06b_streaming_inserts_noindex_PARTITIONED.sql first';
        RETURN;
    END IF;

    -- Display results using dynamic SQL
    RAISE NOTICE '';
    v_query := format('
        SELECT
            variant,
            COUNT(*) AS total_batches,
            SUM(rows_inserted) AS total_rows,
            ROUND(AVG(throughput_rows_sec), 0) AS avg_throughput_rows_sec,
            ROUND(MIN(throughput_rows_sec), 0) AS min_throughput,
            ROUND(MAX(throughput_rows_sec), 0) AS max_throughput,
            ROUND(SUM(duration_ms) / 1000.0, 1) || '' seconds'' AS total_insert_time
        FROM cdr.%I
        GROUP BY variant
        ORDER BY avg_throughput_rows_sec DESC', v_table_name);

    FOR v_result IN EXECUTE v_query LOOP
        RAISE NOTICE 'Variant: %, Batches: %, Rows: %, Avg Throughput: % rows/sec, Min: %, Max: %, Total Time: %',
            v_result.variant, v_result.total_batches, v_result.total_rows,
            v_result.avg_throughput_rows_sec, v_result.min_throughput,
            v_result.max_throughput, v_result.total_insert_time;
    END LOOP;
END $$;

\echo ''

-- =====================================================
-- Section 4: Phase 2 INSERT Performance (With Indexes)
-- =====================================================

\echo 'Section 4: Phase 2 INSERT Performance (With Indexes, Partitioned)'
\echo '=================================================================='
\echo ''

-- Detect and use correct Phase 2 table name (production or test, partitioned)
DO $$
DECLARE
    v_table_name TEXT;
    v_query TEXT;
    v_result RECORD;
BEGIN
    -- Check which table exists (partitioned variants)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2_partitioned_test') THEN
        v_table_name := 'streaming_metrics_phase2_partitioned_test';
        RAISE NOTICE 'Phase 2 metrics found (PARTITIONED TEST run) - analyzing...';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2_partitioned') THEN
        v_table_name := 'streaming_metrics_phase2_partitioned';
        RAISE NOTICE 'Phase 2 metrics found (PARTITIONED PRODUCTION run) - analyzing...';
    ELSE
        RAISE NOTICE 'Phase 2 metrics not found (partitioned table does not exist)';
        RAISE NOTICE 'Run 07b_streaming_inserts_withindex_PARTITIONED.sql to generate Phase 2 metrics';
        RETURN;
    END IF;

    -- Display results using dynamic SQL
    RAISE NOTICE '';
    v_query := format('
        SELECT
            variant,
            COUNT(*) AS total_batches,
            SUM(rows_inserted) AS total_rows,
            ROUND(AVG(throughput_rows_sec), 0) AS avg_throughput_rows_sec,
            ROUND(MIN(throughput_rows_sec), 0) AS min_throughput,
            ROUND(MAX(throughput_rows_sec), 0) AS max_throughput,
            ROUND(SUM(duration_ms) / 1000.0, 1) || '' seconds'' AS total_insert_time
        FROM cdr.%I
        GROUP BY variant
        ORDER BY avg_throughput_rows_sec DESC', v_table_name);

    FOR v_result IN EXECUTE v_query LOOP
        RAISE NOTICE 'Variant: %, Batches: %, Rows: %, Avg Throughput: % rows/sec, Min: %, Max: %, Total Time: %',
            v_result.variant, v_result.total_batches, v_result.total_rows,
            v_result.avg_throughput_rows_sec, v_result.min_throughput,
            v_result.max_throughput, v_result.total_insert_time;
    END LOOP;
END $$;

\echo ''

-- =====================================================
-- Section 5: Phase 1 vs Phase 2 Comparison
-- =====================================================

\echo 'Section 5: Phase 1 vs Phase 2 Comparison (Index Overhead, Partitioned)'
\echo '======================================================================='
\echo ''

-- Compare throughput degradation with indexes (detect table names, partitioned)
DO $$
DECLARE
    v_phase1_table TEXT;
    v_phase2_table TEXT;
    v_query TEXT;
    v_result RECORD;
    v_has_both BOOLEAN := false;
BEGIN
    -- Detect Phase 1 table (partitioned variants)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_partitioned_test') THEN
        v_phase1_table := 'streaming_metrics_phase1_partitioned_test';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_partitioned') THEN
        v_phase1_table := 'streaming_metrics_phase1_partitioned';
    END IF;

    -- Detect Phase 2 table (partitioned variants)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2_partitioned_test') THEN
        v_phase2_table := 'streaming_metrics_phase2_partitioned_test';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2_partitioned') THEN
        v_phase2_table := 'streaming_metrics_phase2_partitioned';
    END IF;

    -- Check if we have both phases
    IF v_phase1_table IS NOT NULL AND v_phase2_table IS NOT NULL THEN
        v_has_both := true;
        RAISE NOTICE 'Both phases complete (partitioned) - comparing...';
        RAISE NOTICE '';
    ELSE
        RAISE NOTICE 'Both phases required for comparison (partitioned variants)';
        RAISE NOTICE 'Current status:';
        IF v_phase1_table IS NOT NULL THEN
            RAISE NOTICE '  ✅ Phase 1 complete (partitioned)';
        ELSE
            RAISE NOTICE '  ❌ Phase 1 incomplete (partitioned)';
        END IF;
        IF v_phase2_table IS NOT NULL THEN
            RAISE NOTICE '  ✅ Phase 2 complete (partitioned)';
        ELSE
            RAISE NOTICE '  ❌ Phase 2 incomplete (partitioned)';
        END IF;
        RETURN;
    END IF;

    -- Run comparison if both exist
    v_query := format('
        WITH phase1_agg AS (
            SELECT variant, AVG(throughput_rows_sec) AS p1_throughput
            FROM cdr.%I
            GROUP BY variant
        ),
        phase2_agg AS (
            SELECT variant, AVG(throughput_rows_sec) AS p2_throughput
            FROM cdr.%I
            GROUP BY variant
        )
        SELECT
            COALESCE(p1.variant, p2.variant) AS variant,
            ROUND(p1.p1_throughput, 0) AS phase1_no_indexes,
            ROUND(p2.p2_throughput, 0) AS phase2_with_indexes,
            ROUND(((p1.p1_throughput - p2.p2_throughput) / p1.p1_throughput * 100), 1) AS degradation_pct
        FROM phase1_agg p1
        FULL OUTER JOIN phase2_agg p2 ON p1.variant = p2.variant
        ORDER BY variant', v_phase1_table, v_phase2_table);

    FOR v_result IN EXECUTE v_query LOOP
        RAISE NOTICE 'Variant: %, Phase 1: % rows/sec, Phase 2: % rows/sec, Degradation: %%%',
            v_result.variant, v_result.phase1_no_indexes,
            v_result.phase2_with_indexes, v_result.degradation_pct;
    END LOOP;
END $$;

\echo ''

-- =====================================================
-- Section 6: Row Count Verification
-- =====================================================

\echo 'Section 6: Row Count Verification (Partitioned Variants)'
\echo '========================================================='
\echo ''

-- Note: COUNT(*) on parent table aggregates all child partitions
SELECT
    'cdr_ao_partitioned' AS table_name,
    COUNT(*)::TEXT AS row_count,
    '(24 partitions)' AS note
FROM cdr.cdr_ao_partitioned

UNION ALL

SELECT 'cdr_aoco_partitioned', COUNT(*)::TEXT, '(24 partitions)'
FROM cdr.cdr_aoco_partitioned

UNION ALL

SELECT 'cdr_pax_partitioned', COUNT(*)::TEXT, '(24 partitions)'
FROM cdr.cdr_pax_partitioned

UNION ALL

SELECT 'cdr_pax_nocluster_partitioned', COUNT(*)::TEXT, '(24 partitions)'
FROM cdr.cdr_pax_nocluster_partitioned;

\echo ''

-- =====================================================
-- Section 7: Partition Distribution (BONUS)
-- =====================================================

\echo 'Section 7: Partition Distribution Analysis (BONUS)'
\echo '==================================================='
\echo ''

\echo 'Rows per partition (sample from AO variant):'
\echo ''

-- Show row distribution across partitions for AO variant
DO $$
DECLARE
    v_partition_name TEXT;
    v_row_count BIGINT;
BEGIN
    RAISE NOTICE 'Partition distribution for cdr_ao_partitioned:';
    RAISE NOTICE '';

    FOR v_partition_name IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'cdr'
          AND tablename LIKE 'cdr_ao_part_day%'
        ORDER BY tablename
        LIMIT 5  -- Show first 5 partitions
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM cdr.%I', v_partition_name) INTO v_row_count;
        RAISE NOTICE '  %: % rows', v_partition_name, v_row_count;
    END LOOP;

    RAISE NOTICE '  ... (19 more partitions)';
    RAISE NOTICE '';
    RAISE NOTICE 'Note: Each partition contains ~1.74M rows (42M ÷ 24)';
END $$;

\echo ''
\echo '===================================================='
\echo 'Metrics collection complete (partitioned variants)!'
\echo '===================================================='
\echo ''
\echo 'Partitioning benefits:'
\echo '  • 24 partitions per variant (96 total tables)'
\echo '  • Each partition: ~1.74M rows (vs 42M monolithic)'
\echo '  • Indexes 24x smaller per partition'
\echo '  • Expected Phase 2 speedup: 18-35% vs monolithic'
\echo ''
\echo 'Next: Phase 11b - Validate results (safety gates, partitioned)'
