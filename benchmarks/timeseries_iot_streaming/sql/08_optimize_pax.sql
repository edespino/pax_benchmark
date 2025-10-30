--
-- Phase 8: Optimize PAX Tables (Z-order Clustering)
-- Applies Z-order clustering to PAX tables after streaming INSERTs complete
-- CRITICAL: Sets maintenance_work_mem based on row count
--

\timing on

\echo '===================================================='
\echo 'Streaming Benchmark - Phase 8: Optimize PAX Tables'
\echo '===================================================='
\echo ''

-- =====================================================
-- Calculate Required Memory
-- =====================================================

\echo 'Calculating required maintenance_work_mem...'

DO $$
DECLARE
    v_row_count BIGINT;
    v_required_mem TEXT;
BEGIN
    -- Get row count from PAX table
    SELECT COUNT(*) INTO v_row_count FROM cdr.cdr_pax;

    RAISE NOTICE 'PAX table row count: %', v_row_count;

    -- Calculate required memory
    SELECT recommended_memory_setting INTO v_required_mem
    FROM cdr_validation.calculate_cluster_memory(v_row_count);

    RAISE NOTICE 'Required maintenance_work_mem: %', v_required_mem;
    RAISE NOTICE '';

    -- Set memory for clustering
    EXECUTE 'SET maintenance_work_mem = ''' || v_required_mem || '''';

    RAISE NOTICE 'maintenance_work_mem set to: %', v_required_mem;
END $$;

\echo ''

-- =====================================================
-- Apply Z-order Clustering to PAX Table
-- =====================================================

\echo 'Applying Z-order clustering to cdr.cdr_pax...'
\echo '  (This may take 2-5 minutes for 50M rows)'
\echo ''

-- PAX tables with cluster_type='zorder' automatically use Z-order
-- No explicit index needed
CLUSTER cdr.cdr_pax;

\echo '  ✓ Z-order clustering applied to cdr_pax'

-- Analyze after clustering
ANALYZE cdr.cdr_pax;

\echo '  ✓ Analysis complete'
\echo ''

-- =====================================================
-- Validate Clustering Results
-- =====================================================

\echo 'Validating clustering overhead...'
\echo ''

SELECT * FROM cdr_validation.detect_storage_bloat(
    'cdr',
    'cdr_pax_nocluster',  -- Baseline
    'cdr_pax'             -- Test (after clustering)
);

\echo ''

-- =====================================================
-- Storage Comparison
-- =====================================================

\echo 'Storage comparison after clustering:'
\echo ''

SELECT
    'PAX no-cluster' AS variant,
    pg_size_pretty(pg_total_relation_size('cdr.cdr_pax_nocluster')) AS size,
    '(baseline)' AS note
UNION ALL
SELECT
    'PAX clustered',
    pg_size_pretty(pg_total_relation_size('cdr.cdr_pax')),
    ROUND(
        (pg_total_relation_size('cdr.cdr_pax')::NUMERIC /
         pg_total_relation_size('cdr.cdr_pax_nocluster')::NUMERIC - 1) * 100,
        1
    )::TEXT || '% overhead' AS note;

\echo ''
\echo '===================================================='
\echo 'PAX optimization complete!'
\echo '===================================================='
\echo ''
\echo 'Expected clustering overhead: 20-30%'
\echo 'If overhead > 50%: Check bloom filter configuration'
\echo ''
\echo 'Next: Phase 9 - Run queries to test performance'
