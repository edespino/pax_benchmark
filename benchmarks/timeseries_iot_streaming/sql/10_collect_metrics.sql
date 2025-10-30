--
-- Phase 10: Collect Comprehensive Metrics
-- Analyzes streaming INSERT performance and storage efficiency
-- Compares Phase 1 (no indexes) vs Phase 2 (with indexes) if available
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 10: Collect Metrics'
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

-- Check if Phase 1 metrics exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase1') THEN
        RAISE NOTICE 'Phase 1 metrics found - analyzing...';
    ELSE
        RAISE NOTICE 'Phase 1 metrics not found (table does not exist)';
        RAISE NOTICE 'Run 06_streaming_inserts_noindex.sql first';
    END IF;
END $$;

\echo ''

-- Aggregate throughput by variant (Phase 1)
SELECT
    variant,
    COUNT(*) AS total_batches,
    SUM(rows_inserted) AS total_rows,
    ROUND(AVG(throughput_rows_sec), 0) AS avg_throughput_rows_sec,
    ROUND(MIN(throughput_rows_sec), 0) AS min_throughput,
    ROUND(MAX(throughput_rows_sec), 0) AS max_throughput,
    pg_size_pretty(SUM(duration_ms) * interval '1 millisecond') AS total_insert_time
FROM cdr.streaming_metrics_phase1
GROUP BY variant
ORDER BY avg_throughput_rows_sec DESC;

\echo ''

-- =====================================================
-- Section 4: Phase 2 INSERT Performance (With Indexes)
-- =====================================================

\echo 'Section 4: Phase 2 INSERT Performance (With Indexes)'
\echo '====================================================='
\echo ''

-- Check if Phase 2 metrics exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2') THEN
        RAISE NOTICE 'Phase 2 metrics found - analyzing...';
    ELSE
        RAISE NOTICE 'Phase 2 metrics not found (table does not exist)';
        RAISE NOTICE 'Run 07_streaming_inserts_withindex.sql to generate Phase 2 metrics';
    END IF;
END $$;

\echo ''

-- Aggregate throughput by variant (Phase 2) - if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'cdr' AND table_name = 'streaming_metrics_phase2') THEN
        RAISE NOTICE 'Phase 2 throughput:';
        PERFORM 1; -- Placeholder, actual query below
    END IF;
END $$;

SELECT
    variant,
    COUNT(*) AS total_batches,
    SUM(rows_inserted) AS total_rows,
    ROUND(AVG(throughput_rows_sec), 0) AS avg_throughput_rows_sec,
    ROUND(MIN(throughput_rows_sec), 0) AS min_throughput,
    ROUND(MAX(throughput_rows_sec), 0) AS max_throughput,
    pg_size_pretty(SUM(duration_ms) * interval '1 millisecond') AS total_insert_time
FROM cdr.streaming_metrics_phase2
GROUP BY variant
ORDER BY avg_throughput_rows_sec DESC;

\echo ''

-- =====================================================
-- Section 5: Phase 1 vs Phase 2 Comparison
-- =====================================================

\echo 'Section 5: Phase 1 vs Phase 2 Comparison (Index Overhead)'
\echo '==========================================================='
\echo ''

-- Compare throughput degradation with indexes
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cdr.streaming_metrics_phase1)
       AND EXISTS (SELECT 1 FROM cdr.streaming_metrics_phase2) THEN
        RAISE NOTICE 'Both phases complete - comparing...';
    ELSE
        RAISE NOTICE 'Both phases required for comparison';
        RAISE NOTICE 'Current status:';
        IF EXISTS (SELECT 1 FROM cdr.streaming_metrics_phase1) THEN
            RAISE NOTICE '  ✅ Phase 1 complete';
        ELSE
            RAISE NOTICE '  ❌ Phase 1 incomplete';
        END IF;
        IF EXISTS (SELECT 1 FROM cdr.streaming_metrics_phase2) THEN
            RAISE NOTICE '  ✅ Phase 2 complete';
        ELSE
            RAISE NOTICE '  ❌ Phase 2 incomplete';
        END IF;
    END IF;
END $$;

\echo ''

-- Comparison query (only if both exist)
WITH phase1_agg AS (
    SELECT variant, AVG(throughput_rows_sec) AS p1_throughput
    FROM cdr.streaming_metrics_phase1
    GROUP BY variant
),
phase2_agg AS (
    SELECT variant, AVG(throughput_rows_sec) AS p2_throughput
    FROM cdr.streaming_metrics_phase2
    GROUP BY variant
)
SELECT
    COALESCE(p1.variant, p2.variant) AS variant,
    ROUND(p1.p1_throughput, 0) AS phase1_no_indexes,
    ROUND(p2.p2_throughput, 0) AS phase2_with_indexes,
    ROUND(((p1.p1_throughput - p2.p2_throughput) / p1.p1_throughput * 100), 1) AS degradation_pct,
    CASE
        WHEN ((p1.p1_throughput - p2.p2_throughput) / p1.p1_throughput) < 0.20 THEN '✅ Low (<20%)'
        WHEN ((p1.p1_throughput - p2.p2_throughput) / p1.p1_throughput) < 0.40 THEN '🟠 Moderate (20-40%)'
        ELSE '❌ High (>40%)'
    END AS index_overhead_assessment
FROM phase1_agg p1
FULL OUTER JOIN phase2_agg p2 ON p1.variant = p2.variant
ORDER BY degradation_pct NULLS LAST;

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
FROM cdr.cdr_pax_nocluster;

\echo ''
\echo '===================================================='
\echo 'Metrics collection complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 11 - Validate results (safety gates)'
