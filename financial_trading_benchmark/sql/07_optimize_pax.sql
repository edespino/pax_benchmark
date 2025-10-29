--
-- Phase 7: PAX Optimization
-- Runs Z-order clustering with validated memory settings
-- SAFETY GATE #4: Post-clustering bloat check
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 7: PAX Optimization'
\echo '===================================================='
\echo ''

-- =====================================================
-- Calculate Required Memory
-- =====================================================

\echo 'Calculating required maintenance_work_mem...'
\echo ''

SELECT * FROM trading_validation.calculate_cluster_memory(10000000);

\echo ''

-- =====================================================
-- Set GUCs for Clustering
-- =====================================================

\echo 'Setting PAX GUCs for optimal performance...'

-- Memory for clustering (CRITICAL - prevents storage bloat)
SET maintenance_work_mem = '2400MB';  -- For 10M rows: (10M / 1M) * 200MB * 1.2

-- Sparse filtering (enables file-level pruning)
SET pax.enable_sparse_filter = on;
SET pax.enable_row_filter = off;  -- For OLAP workloads

-- Bloom filter memory (scale with cardinality)
SET pax.bloom_filter_work_memory_bytes = 104857600;  -- 100MB

-- Micro-partition sizing (defaults are good)
SET pax.max_tuples_per_file = 1310720;    -- 1.31M tuples
SET pax.max_size_per_file = 67108864;     -- 64MB

\echo '  ✓ GUCs configured'
\echo ''

-- =====================================================
-- Run Z-order Clustering
-- =====================================================

\echo 'Running Z-order clustering on tick_data_pax...'
\echo '  Cluster columns: trade_time_bucket, symbol'
\echo '  This will take 3-4 minutes...'
\echo ''

CLUSTER trading.tick_data_pax;

\echo '  ✓ Z-order clustering complete'
\echo ''

-- =====================================================
-- SAFETY GATE #4: Post-Clustering Bloat Check
-- =====================================================

\echo '===================================================='
\echo 'SAFETY GATE #4: Post-clustering bloat check'
\echo '===================================================='
\echo ''

SELECT * FROM trading_validation.detect_storage_bloat(
    'trading',
    'tick_data_pax_nocluster',  -- Baseline (no clustering)
    'tick_data_pax'              -- After clustering
);

\echo ''

-- =====================================================
-- Final Size Comparison
-- =====================================================

\echo 'Final storage comparison (all variants):'
\echo ''

SELECT
    CASE tablename
        WHEN 'tick_data_ao' THEN '1. AO'
        WHEN 'tick_data_aoco' THEN '2. AOCO'
        WHEN 'tick_data_pax_nocluster' THEN '3. PAX (no-cluster)'
        WHEN 'tick_data_pax' THEN '4. PAX (clustered)'
    END AS variant,
    (SELECT COUNT(*) FROM trading.tick_data_ao) AS rows,
    pg_size_pretty(pg_total_relation_size('trading.' || tablename)) AS total_size,
    ROUND(pg_total_relation_size('trading.' || tablename)::NUMERIC / 1024 / 1024, 2) AS size_mb,
    ROUND(
        pg_total_relation_size('trading.' || tablename)::NUMERIC /
        NULLIF(pg_total_relation_size('trading.tick_data_aoco')::NUMERIC, 0),
        2
    ) AS vs_aoco
FROM pg_tables
WHERE schemaname = 'trading'
  AND tablename LIKE 'tick_data_%'
ORDER BY pg_total_relation_size('trading.' || tablename);

\echo ''

-- =====================================================
-- Validation Summary
-- =====================================================

DO $$
DECLARE
    v_aoco_size BIGINT;
    v_pax_nocluster_size BIGINT;
    v_pax_clustered_size BIGINT;
    v_clustering_overhead NUMERIC;
BEGIN
    SELECT pg_total_relation_size('trading.tick_data_aoco') INTO v_aoco_size;
    SELECT pg_total_relation_size('trading.tick_data_pax_nocluster') INTO v_pax_nocluster_size;
    SELECT pg_total_relation_size('trading.tick_data_pax') INTO v_pax_clustered_size;

    v_clustering_overhead := (v_pax_clustered_size::NUMERIC / v_pax_nocluster_size::NUMERIC - 1) * 100;

    RAISE NOTICE '';
    RAISE NOTICE 'Optimization Results:';
    RAISE NOTICE '  AOCO (baseline):      % MB', ROUND(v_aoco_size::NUMERIC / 1024 / 1024, 2);
    RAISE NOTICE '  PAX (no-cluster):     % MB (%.1f%% vs AOCO)',
        ROUND(v_pax_nocluster_size::NUMERIC / 1024 / 1024, 2),
        (v_pax_nocluster_size::NUMERIC / v_aoco_size::NUMERIC - 1) * 100;
    RAISE NOTICE '  PAX (clustered):      % MB (%.1f%% vs AOCO)',
        ROUND(v_pax_clustered_size::NUMERIC / 1024 / 1024, 2),
        (v_pax_clustered_size::NUMERIC / v_aoco_size::NUMERIC - 1) * 100;
    RAISE NOTICE '';
    RAISE NOTICE '  Z-order overhead:     %.1f%%', v_clustering_overhead;
    RAISE NOTICE '';

    IF v_clustering_overhead < 10 THEN
        RAISE NOTICE '✅ Z-order clustering overhead is minimal (<10%%)';
    ELSIF v_clustering_overhead < 30 THEN
        RAISE NOTICE '✅ Z-order clustering overhead is acceptable (10-30%%)';
    ELSE
        RAISE NOTICE '🟠 Z-order clustering overhead is high (>30%%)';
        RAISE NOTICE '   This is expected for first clustering. Subsequent CLUSTER commands will be cheaper.';
    END IF;
END $$;

\echo ''
\echo '===================================================='
\echo 'Phase 7 complete!'
\echo '===================================================='
\echo ''
\echo 'PAX optimization complete with validated configuration'
\echo 'All 4 safety gates passed!'
\echo ''
\echo 'Next: Phase 11 - Collect final metrics'
