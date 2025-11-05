--
-- Phase 10: Collect Comprehensive Metrics
-- Analyzes streaming INSERT performance and storage efficiency
-- Compares Phase 1 (no indexes) vs Phase 2 (with indexes) if available
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 10d: Collect Metrics (WITH HEAP)'
\echo '===================================================='
\echo ''

-- =====================================================
-- Section 1: Storage Comparison
-- =====================================================

\echo 'Section 1: Storage Comparison'
\echo '=============================='
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
        pg_total_relation_size('cdr.cdr_ao') AS table_size,
        (SELECT pg_total_relation_size('cdr.cdr_aoco')) AS aoco_size
    UNION ALL
    SELECT
        'AOCO',
        pg_total_relation_size('cdr.cdr_aoco'),
        pg_total_relation_size('cdr.cdr_aoco')
    UNION ALL
    SELECT
        'PAX',
        pg_total_relation_size('cdr.cdr_pax'),
        pg_total_relation_size('cdr.cdr_aoco')
    UNION ALL
    SELECT
        'PAX-no-cluster',
        pg_total_relation_size('cdr.cdr_pax_nocluster'),
        pg_total_relation_size('cdr.cdr_aoco')
    UNION ALL
    SELECT
        'HEAP',
        pg_total_relation_size('cdr.cdr_heap'),
        pg_total_relation_size('cdr.cdr_aoco')
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
WITH raw_sizes AS (
    SELECT
        'AO' AS variant,
        COUNT(*) AS row_count,
        pg_total_relation_size('cdr.cdr_ao') AS compressed_size
    FROM cdr.cdr_ao
    UNION ALL
    SELECT 'AOCO', COUNT(*), pg_total_relation_size('cdr.cdr_aoco')
    FROM cdr.cdr_aoco
    UNION ALL
    SELECT 'PAX', COUNT(*), pg_total_relation_size('cdr.cdr_pax')
    FROM cdr.cdr_pax
    UNION ALL
    SELECT 'PAX-no-cluster', COUNT(*), pg_total_relation_size('cdr.cdr_pax_nocluster')
    FROM cdr.cdr_pax_nocluster
    UNION ALL
    SELECT 'HEAP', COUNT(*), pg_total_relation_size('cdr.cdr_heap')
    FROM cdr.cdr_heap
)
SELECT
    variant,
    row_count,
    pg_size_pretty(compressed_size) AS compressed,
    -- Estimate: ~200 bytes per CDR row (realistic for telecom)
    pg_size_pretty(row_count * 200) AS estimated_raw,
    ROUND((row_count * 200)::NUMERIC / compressed_size::NUMERIC, 2) AS compression_ratio
FROM raw_sizes
ORDER BY compression_ratio DESC;

\echo ''

-- =====================================================
-- Section 3: Phase 1 INSERT Performance (No Indexes)
-- =====================================================

\echo 'Section 3: Phase 1 INSERT Performance (No Indexes)'
\echo '==================================================='
\echo ''

-- Detect and use correct Phase 1 table name (production or test)
DO $$
DECLARE
    v_table_name TEXT;
    v_query TEXT;
    v_result RECORD;
BEGIN
    -- Check which table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_test') THEN
        v_table_name := 'streaming_metrics_phase1_test';
        RAISE NOTICE 'Phase 1 metrics found (TEST run) - analyzing...';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1') THEN
        v_table_name := 'streaming_metrics_phase1';
        RAISE NOTICE 'Phase 1 metrics found (PRODUCTION run) - analyzing...';
    ELSE
        RAISE NOTICE 'Phase 1 metrics not found (table does not exist)';
        RAISE NOTICE 'Run 06_streaming_inserts_noindex.sql first';
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

\echo 'Section 4: Phase 2 INSERT Performance (With Indexes)'
\echo '====================================================='
\echo ''

-- Detect and use correct Phase 2 table name (production or test)
DO $$
DECLARE
    v_table_name TEXT;
    v_query TEXT;
    v_result RECORD;
BEGIN
    -- Check which table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2_test') THEN
        v_table_name := 'streaming_metrics_phase2_test';
        RAISE NOTICE 'Phase 2 metrics found (TEST run) - analyzing...';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2') THEN
        v_table_name := 'streaming_metrics_phase2';
        RAISE NOTICE 'Phase 2 metrics found (PRODUCTION run) - analyzing...';
    ELSE
        RAISE NOTICE 'Phase 2 metrics not found (table does not exist)';
        RAISE NOTICE 'Run 07_streaming_inserts_withindex.sql to generate Phase 2 metrics';
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

\echo 'Section 5: Phase 1 vs Phase 2 Comparison (Index Overhead)'
\echo '==========================================================='
\echo ''

-- Compare throughput degradation with indexes (detect table names)
DO $$
DECLARE
    v_phase1_table TEXT;
    v_phase2_table TEXT;
    v_query TEXT;
    v_result RECORD;
    v_has_both BOOLEAN := false;
BEGIN
    -- Detect Phase 1 table
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1_test') THEN
        v_phase1_table := 'streaming_metrics_phase1_test';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1') THEN
        v_phase1_table := 'streaming_metrics_phase1';
    END IF;

    -- Detect Phase 2 table
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2_test') THEN
        v_phase2_table := 'streaming_metrics_phase2_test';
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2') THEN
        v_phase2_table := 'streaming_metrics_phase2';
    END IF;

    -- Check if we have both phases
    IF v_phase1_table IS NOT NULL AND v_phase2_table IS NOT NULL THEN
        v_has_both := true;
        RAISE NOTICE 'Both phases complete - comparing...';
        RAISE NOTICE '';
    ELSE
        RAISE NOTICE 'Both phases required for comparison';
        RAISE NOTICE 'Current status:';
        IF v_phase1_table IS NOT NULL THEN
            RAISE NOTICE '  ✅ Phase 1 complete';
        ELSE
            RAISE NOTICE '  ❌ Phase 1 incomplete';
        END IF;
        IF v_phase2_table IS NOT NULL THEN
            RAISE NOTICE '  ✅ Phase 2 complete';
        ELSE
            RAISE NOTICE '  ❌ Phase 2 incomplete';
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

\echo 'Section 6: Row Count Verification'
\echo '=================================='
\echo ''

SELECT
    'cdr_ao' AS table_name,
    COUNT(*)::TEXT AS row_count
FROM cdr.cdr_ao

UNION ALL

SELECT 'cdr_aoco', COUNT(*)::TEXT
FROM cdr.cdr_aoco

UNION ALL

SELECT 'cdr_pax', COUNT(*)::TEXT
FROM cdr.cdr_pax

UNION ALL

SELECT 'cdr_pax_nocluster', COUNT(*)::TEXT
FROM cdr.cdr_pax_nocluster

UNION ALL

SELECT 'cdr_heap', COUNT(*)::TEXT
FROM cdr.cdr_heap;

\echo ''
\echo '===================================================='
\echo 'Metrics collection complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 11 - Validate results (safety gates)'
