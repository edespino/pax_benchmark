--
-- Phase 6: Optimize PAX (Z-order Clustering)
-- Runs CLUSTER on PAX variant with validated memory settings
-- This is where clustering overhead appears (if misconfigured)
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 6: PAX Optimization'
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
    SELECT recommended_maintenance_work_mem INTO required_mem
    FROM logs_validation.calculate_cluster_memory(10000000);

    RAISE NOTICE 'Required maintenance_work_mem: %', required_mem;
    EXECUTE 'SET maintenance_work_mem = ''' || required_mem || '''';
END $$;

\echo ''
\echo 'Current settings:'
SHOW maintenance_work_mem;
\echo ''

-- =====================================================
-- Additional PAX-specific Settings
-- =====================================================

\echo 'Configuring PAX optimization settings...'
\echo ''

-- Enable sparse filtering (file-level pruning via zone maps)
SET pax.enable_sparse_filter = on;

-- Row filter generally OFF for OLAP workloads (use sparse filter instead)
SET pax.enable_row_filter = off;

-- Bloom filter work memory (100MB for high-cardinality columns)
SET pax.bloom_filter_work_memory_bytes = 104857600;

\echo '  ✓ PAX settings configured'
\echo ''

-- =====================================================
-- Z-order Clustering on PAX Variant
-- =====================================================

\echo 'Running Z-order CLUSTER on log_entries_pax...'
\echo '  Clustering on: (log_date, application_id)'
\echo '  (This will take 1-2 minutes for 10M rows)'
\echo ''

-- Note: PAX tables with cluster_type='zorder' automatically use Z-order clustering
-- No explicit index needed - CLUSTER uses built-in Z-order implementation
CLUSTER logs.log_entries_pax;

\echo '  ✓ Z-order clustering complete'
\echo ''

-- =====================================================
-- ANALYZE After Clustering
-- =====================================================

\echo 'Running ANALYZE after clustering...'

ANALYZE logs.log_entries_pax;

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
        WHEN tablename = 'log_entries_ao' THEN 'AO'
        WHEN tablename = 'log_entries_aoco' THEN 'AOCO'
        WHEN tablename = 'log_entries_pax' THEN 'PAX (CLUSTERED)'
        WHEN tablename = 'log_entries_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant,
    pg_size_pretty(pg_total_relation_size('logs.' || tablename)) AS total_size,
    pg_total_relation_size('logs.' || tablename) / 1024 / 1024 AS size_mb,
    ROUND((pg_total_relation_size('logs.' || tablename)::NUMERIC /
           NULLIF(pg_total_relation_size('logs.log_entries_aoco')::NUMERIC, 0)), 2) AS ratio_vs_aoco,
    CASE
        WHEN tablename = 'log_entries_pax' THEN
            ROUND((pg_total_relation_size('logs.log_entries_pax')::NUMERIC /
                   pg_total_relation_size('logs.log_entries_pax_nocluster')::NUMERIC), 2)
        ELSE NULL
    END AS clustering_overhead
FROM pg_tables
WHERE schemaname = 'logs'
  AND tablename LIKE 'log_entries_%'
ORDER BY pg_total_relation_size('logs.' || tablename) DESC;

\echo ''

-- =====================================================
-- VALIDATION: Post-Clustering Bloat Check
-- =====================================================

\echo '===================================================='
\echo '⚠️  VALIDATION: Post-clustering bloat check'
\echo '===================================================='
\echo ''

SELECT * FROM logs_validation.detect_storage_bloat(
    'log_entries_pax_nocluster',  -- Baseline
    'log_entries_pax',            -- After clustering
    'logs'                        -- Schema
);

\echo ''

-- =====================================================
-- Clustering Impact Analysis
-- =====================================================

\echo 'Clustering impact analysis:'
\echo ''

WITH sizes AS (
    SELECT
        pg_total_relation_size('logs.log_entries_pax_nocluster') AS nocluster_size,
        pg_total_relation_size('logs.log_entries_pax') AS clustered_size
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
-- Sparse Field Efficiency Check
-- =====================================================

\echo '===================================================='
\echo 'SPARSE FIELD EFFICIENCY (PAX Advantage)'
\echo '===================================================='
\echo ''
\echo 'Checking storage efficiency for sparse columns:'
\echo '  - stack_trace (95% NULL)'
\echo '  - error_code (95% NULL)'
\echo '  - user_id (30% NULL)'
\echo ''

-- Query to show NULL percentages
WITH null_analysis AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(stack_trace) AS stack_trace_non_null,
        COUNT(error_code) AS error_code_non_null,
        COUNT(user_id) AS user_id_non_null,
        COUNT(session_id) AS session_id_non_null
    FROM logs.log_entries_pax
    LIMIT 1000000  -- Sample first 1M rows for speed
)
SELECT
    'stack_trace' AS column_name,
    ROUND(100.0 * (total_rows - stack_trace_non_null) / total_rows, 1) || '%' AS null_percentage,
    '~95% expected' AS target
FROM null_analysis
UNION ALL
SELECT
    'error_code',
    ROUND(100.0 * (total_rows - error_code_non_null) / total_rows, 1) || '%',
    '~95% expected'
FROM null_analysis
UNION ALL
SELECT
    'user_id',
    ROUND(100.0 * (total_rows - user_id_non_null) / total_rows, 1) || '%',
    '~30% expected'
FROM null_analysis
UNION ALL
SELECT
    'session_id',
    ROUND(100.0 * (total_rows - session_id_non_null) / total_rows, 1) || '%',
    '~30% expected'
FROM null_analysis;

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
    SELECT pg_total_relation_size('logs.log_entries_pax') INTO pax_size;
    SELECT pg_total_relation_size('logs.log_entries_pax_nocluster') INTO pax_nocluster_size;
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
\echo 'Next: Phase 7 - Run query suite'
\echo 'Run: psql -f sql/07_run_queries.sql'
\echo ''
