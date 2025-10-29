--
-- Phase 7: Optimize PAX (Z-order Clustering)
-- Runs CLUSTER on PAX variant with validated memory settings
-- This is where clustering overhead appears (if misconfigured)
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 7: PAX Optimization'
\echo '===================================================='
\echo ''

-- =====================================================
-- Set Memory for Clustering (From Phase 3 calculation)
-- =====================================================

\echo 'Setting maintenance_work_mem for Z-order clustering...'

-- Get calculated memory requirement from validation framework
DO $$
DECLARE
    required_mem TEXT;
BEGIN
    SELECT recommended_memory_setting INTO required_mem
    FROM iot_validation.calculate_cluster_memory(10000000);

    RAISE NOTICE 'Required maintenance_work_mem: %', required_mem;
    EXECUTE 'SET maintenance_work_mem = ''' || required_mem || '''';
END $$;

\echo ''
\echo 'Current settings:'
SHOW maintenance_work_mem;
\echo ''

-- =====================================================
-- Z-order Clustering on PAX Variant
-- =====================================================

\echo 'Running Z-order CLUSTER on readings_pax...'
\echo '  (This will take 1-2 minutes for 10M rows)'
\echo ''

-- Note: PAX tables with cluster_type='zorder' automatically use Z-order clustering
-- No explicit index needed - CLUSTER uses built-in Z-order implementation
CLUSTER iot.readings_pax;

\echo '  ✓ Z-order clustering complete'
\echo ''

-- =====================================================
-- ANALYZE After Clustering
-- =====================================================

\echo 'Running ANALYZE after clustering...'

ANALYZE iot.readings_pax;

\echo '  ✓ ANALYZE complete'
\echo ''

-- =====================================================
-- Post-Clustering Storage Comparison
-- =====================================================

\echo 'Storage comparison (after clustering):'
\echo ''

SELECT
    tablename,
    CASE
        WHEN tablename = 'readings_ao' THEN 'AO'
        WHEN tablename = 'readings_aoco' THEN 'AOCO'
        WHEN tablename = 'readings_pax' THEN 'PAX (CLUSTERED)'
        WHEN tablename = 'readings_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS total_size,
    pg_total_relation_size('iot.' || tablename) / 1024 / 1024 AS size_mb,
    ROUND((pg_total_relation_size('iot.' || tablename)::NUMERIC /
           NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)), 2) AS ratio_vs_aoco,
    CASE
        WHEN tablename = 'readings_pax' THEN
            ROUND((pg_total_relation_size('iot.readings_pax')::NUMERIC /
                   pg_total_relation_size('iot.readings_pax_nocluster')::NUMERIC), 2)
        ELSE NULL
    END AS clustering_overhead
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY pg_total_relation_size('iot.' || tablename) DESC;

\echo ''

-- =====================================================
-- SAFETY GATE #4: Post-Clustering Bloat Check
-- =====================================================

\echo '===================================================='
\echo '⚠️  SAFETY GATE #4: Post-clustering bloat check'
\echo '===================================================='
\echo ''

SELECT * FROM iot_validation.detect_storage_bloat(
    'iot',
    'readings_pax_nocluster',  -- Baseline
    'readings_pax'             -- After clustering
);

\echo ''

-- =====================================================
-- Clustering Impact Analysis
-- =====================================================

\echo 'Clustering impact analysis:'
\echo ''

WITH sizes AS (
    SELECT
        pg_total_relation_size('iot.readings_pax_nocluster') AS nocluster_size,
        pg_total_relation_size('iot.readings_pax') AS clustered_size
)
SELECT
    'Before clustering' AS phase,
    pg_size_pretty(nocluster_size) AS pax_size,
    '-' AS change
FROM sizes
UNION ALL
SELECT
    'After clustering',
    pg_size_pretty(clustered_size),
    '+' || pg_size_pretty(clustered_size - nocluster_size) || ' (' ||
    ROUND(((clustered_size::NUMERIC / nocluster_size::NUMERIC) - 1) * 100, 1) || '%)'
FROM sizes;

\echo ''

-- =====================================================
-- Final Validation
-- =====================================================

DO $$
DECLARE
    pax_size BIGINT;
    pax_nocluster_size BIGINT;
    bloat_ratio NUMERIC;
BEGIN
    SELECT pg_total_relation_size('iot.readings_pax') INTO pax_size;
    SELECT pg_total_relation_size('iot.readings_pax_nocluster') INTO pax_nocluster_size;
    bloat_ratio := pax_size::NUMERIC / pax_nocluster_size::NUMERIC;

    RAISE NOTICE '';
    RAISE NOTICE 'Post-clustering validation:';
    RAISE NOTICE '  Clustering overhead: %x', ROUND(bloat_ratio, 2);
    RAISE NOTICE '';

    IF bloat_ratio < 1.1 THEN
        RAISE NOTICE '✅ EXCELLENT: Clustering added minimal overhead (<10%%)';
    ELSIF bloat_ratio < 1.3 THEN
        RAISE NOTICE '✅ GOOD: Clustering overhead acceptable (10-30%%)';
    ELSIF bloat_ratio < 1.5 THEN
        RAISE NOTICE '🟠 WARNING: Clustering overhead high (30-50%%)';
        RAISE NOTICE '   Expected: <30%%';
        RAISE NOTICE '   Check maintenance_work_mem was sufficient';
    ELSE
        RAISE NOTICE '❌ CRITICAL: Clustering caused bloat (>50%%)';
        RAISE NOTICE '   Possible causes:';
        RAISE NOTICE '     1. Insufficient maintenance_work_mem';
        RAISE NOTICE '     2. Bloom filters on low-cardinality columns';
        RAISE EXCEPTION 'Clustering validation FAILED - bloat ratio: %', bloat_ratio;
    END IF;
END $$;

\echo ''
\echo '===================================================='
\echo 'PAX optimization complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 8 - Run query suite'
