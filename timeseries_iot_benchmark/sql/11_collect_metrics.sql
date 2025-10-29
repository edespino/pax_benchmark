--
-- Phase 11: Collect Metrics
-- Final comparison of AO vs AOCO vs PAX variants
-- Storage, compression, and performance summary
--

\timing on

\echo '===================================================='
\echo 'IoT Benchmark - Phase 11: Final Metrics Collection'
\echo '===================================================='
\echo ''

-- =====================================================
-- Storage Comparison (Final)
-- =====================================================

\echo '===================================================='
\echo 'STORAGE COMPARISON - ALL VARIANTS'
\echo '===================================================='
\echo ''

SELECT
    CASE
        WHEN tablename = 'readings_ao' THEN '1. AO'
        WHEN tablename = 'readings_aoco' THEN '2. AOCO'
        WHEN tablename = 'readings_pax_nocluster' THEN '3. PAX (no-cluster)'
        WHEN tablename = 'readings_pax' THEN '4. PAX (clustered)'
    END AS variant,
    (SELECT COUNT(*) FROM iot.readings_ao) AS row_count,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS total_size,
    ROUND(pg_total_relation_size('iot.' || tablename) / 1024.0 / 1024.0, 2) AS size_mb,
    ROUND((pg_total_relation_size('iot.' || tablename)::NUMERIC /
           NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)), 2) AS vs_aoco,
    CASE
        WHEN pg_total_relation_size('iot.' || tablename) =
             (SELECT MIN(pg_total_relation_size('iot.' || t))
              FROM pg_tables t
              WHERE t.schemaname = 'iot' AND t.tablename LIKE 'readings_%')
        THEN '🏆 Smallest'
        WHEN (pg_total_relation_size('iot.' || tablename)::NUMERIC /
              NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)) < 1.1
        THEN '✅ Excellent'
        WHEN (pg_total_relation_size('iot.' || tablename)::NUMERIC /
              NULLIF(pg_total_relation_size('iot.readings_aoco')::NUMERIC, 0)) < 1.3
        THEN '🟠 Acceptable'
        ELSE '❌ High overhead'
    END AS assessment
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY pg_total_relation_size('iot.' || tablename);

\echo ''

-- =====================================================
-- Compression Ratio Analysis
-- =====================================================

\echo '===================================================='
\echo 'COMPRESSION EFFECTIVENESS'
\echo '===================================================='
\echo ''

WITH raw_size AS (
    SELECT
        COUNT(*) AS total_rows,
        (COUNT(*) * 200) / 1024 / 1024 AS estimated_raw_mb  -- ~200 bytes/row
    FROM iot.readings_ao
)
SELECT
    CASE
        WHEN tablename = 'readings_ao' THEN '1. AO'
        WHEN tablename = 'readings_aoco' THEN '2. AOCO'
        WHEN tablename = 'readings_pax_nocluster' THEN '3. PAX (no-cluster)'
        WHEN tablename = 'readings_pax' THEN '4. PAX (clustered)'
    END AS variant,
    pg_size_pretty((SELECT estimated_raw_mb * 1024 * 1024 FROM raw_size)::BIGINT) AS estimated_raw,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS compressed,
    ROUND((SELECT estimated_raw_mb FROM raw_size) /
          (pg_total_relation_size('iot.' || tablename)::NUMERIC / 1024 / 1024), 2) AS compression_ratio,
    CASE
        WHEN ROUND((SELECT estimated_raw_mb FROM raw_size) /
                   (pg_total_relation_size('iot.' || tablename)::NUMERIC / 1024 / 1024), 2) >=
             (SELECT MAX(ROUND((estimated_raw_mb) /
                              (pg_total_relation_size('iot.' || t)::NUMERIC / 1024 / 1024), 2))
              FROM pg_tables t, raw_size
              WHERE t.schemaname = 'iot' AND t.tablename LIKE 'readings_%')
        THEN '🏆 Best'
        WHEN ROUND((SELECT estimated_raw_mb FROM raw_size) /
                   (pg_total_relation_size('iot.' || tablename)::NUMERIC / 1024 / 1024), 2) >= 6.0
        THEN '✅ Excellent'
        WHEN ROUND((SELECT estimated_raw_mb FROM raw_size) /
                   (pg_total_relation_size('iot.' || tablename)::NUMERIC / 1024 / 1024), 2) >= 4.0
        THEN '🟠 Good'
        ELSE '❌ Poor'
    END AS rating
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY
    ROUND((SELECT estimated_raw_mb FROM raw_size) /
          (pg_total_relation_size('iot.' || tablename)::NUMERIC / 1024 / 1024), 2) DESC;

\echo ''

-- =====================================================
-- Storage Breakdown
-- =====================================================

\echo '===================================================='
\echo 'STORAGE BREAKDOWN'
\echo '===================================================='
\echo ''

SELECT
    CASE
        WHEN tablename = 'readings_ao' THEN '1. AO'
        WHEN tablename = 'readings_aoco' THEN '2. AOCO'
        WHEN tablename = 'readings_pax_nocluster' THEN '3. PAX (no-cluster)'
        WHEN tablename = 'readings_pax' THEN '4. PAX (clustered)'
    END AS variant,
    pg_size_pretty(pg_relation_size('iot.' || tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename) -
                   pg_relation_size('iot.' || tablename)) AS indexes_toast,
    pg_size_pretty(pg_total_relation_size('iot.' || tablename)) AS total_size
FROM pg_tables
WHERE schemaname = 'iot'
  AND tablename LIKE 'readings_%'
ORDER BY tablename;

\echo ''

-- =====================================================
-- PAX-Specific Metrics
-- =====================================================

\echo '===================================================='
\echo 'PAX CONFIGURATION OVERHEAD'
\echo '===================================================='
\echo ''

WITH pax_comparison AS (
    SELECT
        pg_total_relation_size('iot.readings_pax_nocluster') AS nocluster_size,
        pg_total_relation_size('iot.readings_pax') AS clustered_size,
        pg_total_relation_size('iot.readings_aoco') AS aoco_size
)
SELECT
    'PAX (no-cluster) vs AOCO' AS comparison,
    pg_size_pretty(nocluster_size) AS pax_size,
    pg_size_pretty(aoco_size) AS baseline_size,
    pg_size_pretty(nocluster_size - aoco_size) AS overhead,
    ROUND(((nocluster_size::NUMERIC / aoco_size::NUMERIC) - 1) * 100, 1) || '%' AS overhead_pct,
    CASE
        WHEN ((nocluster_size::NUMERIC / aoco_size::NUMERIC) - 1) < 0.1 THEN '✅ Excellent (<10%)'
        WHEN ((nocluster_size::NUMERIC / aoco_size::NUMERIC) - 1) < 0.2 THEN '🟠 Acceptable (10-20%)'
        ELSE '❌ High (>20%)'
    END AS assessment
FROM pax_comparison
UNION ALL
SELECT
    'PAX (clustered) vs no-cluster',
    pg_size_pretty(clustered_size),
    pg_size_pretty(nocluster_size),
    pg_size_pretty(clustered_size - nocluster_size),
    ROUND(((clustered_size::NUMERIC / nocluster_size::NUMERIC) - 1) * 100, 1) || '%',
    CASE
        WHEN ((clustered_size::NUMERIC / nocluster_size::NUMERIC) - 1) < 0.1 THEN '✅ Excellent (<10%)'
        WHEN ((clustered_size::NUMERIC / nocluster_size::NUMERIC) - 1) < 0.3 THEN '🟠 Acceptable (10-30%)'
        ELSE '❌ High (>30%)'
    END
FROM pax_comparison
UNION ALL
SELECT
    'PAX (clustered) vs AOCO',
    pg_size_pretty(clustered_size),
    pg_size_pretty(aoco_size),
    pg_size_pretty(clustered_size - aoco_size),
    ROUND(((clustered_size::NUMERIC / aoco_size::NUMERIC) - 1) * 100, 1) || '%',
    CASE
        WHEN ((clustered_size::NUMERIC / aoco_size::NUMERIC) - 1) < 0.2 THEN '✅ Excellent (<20%)'
        WHEN ((clustered_size::NUMERIC / aoco_size::NUMERIC) - 1) < 0.4 THEN '🟠 Acceptable (20-40%)'
        ELSE '❌ High (>40%)'
    END
FROM pax_comparison;

\echo ''

-- =====================================================
-- Summary Statistics
-- =====================================================

\echo '===================================================='
\echo 'SUMMARY'
\echo '===================================================='
\echo ''

DO $$
DECLARE
    ao_size BIGINT;
    aoco_size BIGINT;
    pax_nocluster_size BIGINT;
    pax_clustered_size BIGINT;
    row_count BIGINT;
    smallest_variant TEXT;
    best_compression NUMERIC;
BEGIN
    SELECT pg_total_relation_size('iot.readings_ao') INTO ao_size;
    SELECT pg_total_relation_size('iot.readings_aoco') INTO aoco_size;
    SELECT pg_total_relation_size('iot.readings_pax_nocluster') INTO pax_nocluster_size;
    SELECT pg_total_relation_size('iot.readings_pax') INTO pax_clustered_size;
    SELECT COUNT(*) INTO row_count FROM iot.readings_ao;

    -- Find smallest
    IF pax_nocluster_size <= aoco_size AND pax_nocluster_size <= ao_size AND pax_nocluster_size <= pax_clustered_size THEN
        smallest_variant := 'PAX (no-cluster)';
    ELSIF aoco_size <= ao_size AND aoco_size <= pax_clustered_size THEN
        smallest_variant := 'AOCO';
    ELSIF ao_size <= pax_clustered_size THEN
        smallest_variant := 'AO';
    ELSE
        smallest_variant := 'PAX (clustered)';
    END IF;

    RAISE NOTICE 'Dataset: % rows', row_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Storage sizes:';
    RAISE NOTICE '  AO:                 % MB (%.2fx vs AOCO)', ROUND(ao_size / 1024.0 / 1024.0, 2), ROUND(ao_size::NUMERIC / aoco_size::NUMERIC, 2);
    RAISE NOTICE '  AOCO:               % MB (baseline)', ROUND(aoco_size / 1024.0 / 1024.0, 2);
    RAISE NOTICE '  PAX (no-cluster):   % MB (%.2fx vs AOCO)', ROUND(pax_nocluster_size / 1024.0 / 1024.0, 2), ROUND(pax_nocluster_size::NUMERIC / aoco_size::NUMERIC, 2);
    RAISE NOTICE '  PAX (clustered):    % MB (%.2fx vs AOCO)', ROUND(pax_clustered_size / 1024.0 / 1024.0, 2), ROUND(pax_clustered_size::NUMERIC / aoco_size::NUMERIC, 2);
    RAISE NOTICE '';
    RAISE NOTICE 'Smallest variant: %', smallest_variant;
    RAISE NOTICE 'Clustering overhead: %.1f%%', ((pax_clustered_size::NUMERIC / pax_nocluster_size::NUMERIC) - 1) * 100;
    RAISE NOTICE '';

    IF pax_nocluster_size::NUMERIC / aoco_size::NUMERIC <= 1.1 THEN
        RAISE NOTICE '✅ PAX (no-cluster) is competitive with AOCO (<=10%% overhead)';
    ELSIF pax_nocluster_size::NUMERIC / aoco_size::NUMERIC <= 1.2 THEN
        RAISE NOTICE '🟠 PAX (no-cluster) has acceptable overhead (10-20%%)';
    ELSE
        RAISE NOTICE '❌ PAX (no-cluster) has high overhead (>20%%)';
        RAISE NOTICE '   Review bloom filter configuration';
    END IF;

    IF pax_clustered_size::NUMERIC / pax_nocluster_size::NUMERIC <= 1.1 THEN
        RAISE NOTICE '✅ Z-order clustering has minimal overhead (<=10%%)';
    ELSIF pax_clustered_size::NUMERIC / pax_nocluster_size::NUMERIC <= 1.3 THEN
        RAISE NOTICE '🟠 Z-order clustering has acceptable overhead (10-30%%)';
    ELSE
        RAISE NOTICE '❌ Z-order clustering has high overhead (>30%%)';
        RAISE NOTICE '   Check maintenance_work_mem was sufficient';
    END IF;
END $$;

\echo ''
\echo '===================================================='
\echo 'Metrics collection complete!'
\echo '===================================================='
\echo ''
\echo 'All results saved to results/ directory'
\echo 'Review timing.txt for phase-by-phase breakdown'
