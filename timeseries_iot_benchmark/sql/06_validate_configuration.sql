--
-- Phase 6: Validate Configuration (Post-Creation Check)
-- Checks for storage bloat before clustering
-- SAFETY GATE #3
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 6: Configuration Validation'
\echo '===================================================='
\echo ''
\echo '⚠️  SAFETY GATE #3: Post-creation bloat detection'
\echo ''

-- =====================================================
-- Storage Comparison Before Clustering
-- =====================================================

\echo 'Storage comparison (before clustering):'
\echo ''

SELECT
    tablename,
    CASE
        WHEN tablename = 'readings_ao' THEN 'AO'
        WHEN tablename = 'readings_aoco' THEN 'AOCO'
        WHEN tablename = 'readings_pax' THEN 'PAX (unclustered)'
        WHEN tablename = 'readings_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS total_size,
    pg_total_relation_size('iot.' || tablename) / 1024 / 1024 AS size_mb,
    ROUND((pg_total_relation_size('iot.' || tablename)::NUMERIC /
           NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)), 2) AS ratio_vs_aoco,
    CASE
        WHEN (pg_total_relation_size('iot.' || tablename)::NUMERIC /
              NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)) < 1.1 THEN '✅ Good'
        WHEN (pg_total_relation_size('iot.' || tablename)::NUMERIC /
              NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)) < 1.3 THEN '🟠 Acceptable'
        ELSE '❌ Warning'
    END AS status
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY pg_total_relation_size('iot.' || tablename) DESC;

\echo ''

-- =====================================================
-- PAX-Specific Validation (Using validation framework)
-- =====================================================

\echo 'PAX-specific validation:'
\echo ''

-- Check PAX vs PAX no-cluster
SELECT * FROM iot_validation.detect_storage_bloat(
    'iot',
    'readings_pax_nocluster',  -- Baseline (no clustering overhead)
    'readings_pax'             -- Test (with clustering config)
);

\echo ''

-- =====================================================
-- Compression Ratio Analysis
-- =====================================================

\echo 'Compression effectiveness:'
\echo ''

WITH raw_size AS (
    SELECT (COUNT(*) * 200) / 1024 / 1024 AS estimated_raw_mb  -- ~200 bytes/row estimate
    FROM iot.readings_ao
)
SELECT
    tablename,
    CASE
        WHEN tablename = 'readings_ao' THEN 'AO'
        WHEN tablename = 'readings_aoco' THEN 'AOCO'
        WHEN tablename = 'readings_pax' THEN 'PAX (unclustered)'
        WHEN tablename = 'readings_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS compressed_size,
    pg_size_pretty((SELECT estimated_raw_mb * 1024 * 1024 FROM raw_size)::BIGINT) AS estimated_raw_size,
    ROUND((SELECT estimated_raw_mb FROM raw_size) /
          (pg_total_relation_size('iot.' || tablename)::NUMERIC / 1024 / 1024), 2) AS compression_ratio
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY compression_ratio DESC;

\echo ''

-- =====================================================
-- Bloat Check Summary
-- =====================================================

\echo '===================================================='
\echo 'Validation Summary'
\echo '===================================================='
\echo ''

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
    RAISE NOTICE 'PAX (unclustered) vs PAX (no-cluster):';
    RAISE NOTICE '  PAX (unclustered):  % MB', ROUND(pax_size / 1024.0 / 1024.0, 2);
    RAISE NOTICE '  PAX (no-cluster):   % MB', ROUND(pax_nocluster_size / 1024.0 / 1024.0, 2);
    RAISE NOTICE '  Bloat ratio:        %x', ROUND(bloat_ratio, 2);
    RAISE NOTICE '';

    IF bloat_ratio < 1.1 THEN
        RAISE NOTICE '✅ HEALTHY: PAX configuration is optimal (<10%% overhead)';
    ELSIF bloat_ratio < 1.3 THEN
        RAISE NOTICE '🟠 ACCEPTABLE: PAX has minor overhead (10-30%%)';
    ELSIF bloat_ratio < 1.5 THEN
        RAISE NOTICE '⚠️  WARNING: PAX overhead is high (30-50%%)';
        RAISE NOTICE '   Review bloom filter configuration';
    ELSE
        RAISE NOTICE '❌ CRITICAL: PAX bloat detected (>50%%)';
        RAISE NOTICE '   Likely causes:';
        RAISE NOTICE '     1. Bloom filters on low-cardinality columns';
        RAISE NOTICE '     2. Review sql/02_analyze_cardinality.sql output';
        RAISE EXCEPTION 'Configuration validation FAILED - bloat ratio: %', bloat_ratio;
    END IF;
END $$;

\echo ''
\echo '===================================================='
\echo 'Configuration validation complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 7 - Optimize PAX (Z-order clustering)'
