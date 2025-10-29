--
-- Phase 4: PAX Optimization & Clustering
-- Configure optimal GUCs and execute Z-order clustering
--

\echo '================================================'
\echo 'PAX Benchmark - Phase 4: Optimization'
\echo '================================================'
\echo ''

\timing on

-- =============================================
-- Configure Optimal PAX GUCs for OLAP workload
-- =============================================

\echo 'Setting optimal PAX configuration for OLAP...'
\echo ''

-- Enable sparse filtering (zone maps + bloom filters)
SET pax.enable_sparse_filter = on;
\echo '  ✓ Sparse filtering: ENABLED'

-- Disable row filter (better for pure OLAP column access)
SET pax.enable_row_filter = off;
\echo '  ✓ Row filtering: DISABLED (optimized for OLAP)'

-- Optimize micro-partition sizing
SET pax.max_tuples_per_file = 1310720;    -- ~1.3M tuples/file
\echo '  ✓ Max tuples per file: 1,310,720'

SET pax.max_size_per_file = 67108864;     -- 64MB files
\echo '  ✓ Max file size: 64MB'

SET pax.max_tuples_per_group = 131072;    -- 128K tuples/group
\echo '  ✓ Max tuples per group: 131,072'

-- Bloom filter memory
SET pax.bloom_filter_work_memory_bytes = 10485760;  -- 10MB
\echo '  ✓ Bloom filter work memory: 10MB'

\echo ''
\echo 'GUC configuration complete'
\echo ''

-- =============================================
-- Verify Pre-Clustering Statistics
-- NOTE: get_pax_aux_table() not available in this PAX version
-- =============================================

\echo 'Pre-clustering PAX table statistics:'
\echo ''
\echo '  (PAX introspection functions not available in this version)'
\echo '  Table sizes before clustering:'

SELECT
    'PAX (to be clustered)' AS variant,
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_pax')) AS size
UNION ALL
SELECT
    'PAX no-cluster (control)',
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_pax_nocluster'));

\echo ''

-- =============================================
-- Execute Z-Order Clustering
-- Clusters on (sale_date, region) for correlated access
-- =============================================

\echo 'Executing Z-order clustering on (sale_date, region)...'
\echo 'This will reorganize data for optimal multi-dimensional query performance'
\echo 'Estimated time: 10-20 minutes'
\echo ''

CLUSTER benchmark.sales_fact_pax;

\echo ''
\echo 'Z-order clustering complete!'
\echo ''

-- =============================================
-- Verify Post-Clustering Statistics
-- =============================================

\echo 'Post-clustering PAX table statistics:'
\echo ''
\echo '  Table sizes after clustering:'

SELECT
    'PAX (clustered)' AS variant,
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_pax')) AS size
UNION ALL
SELECT
    'PAX no-cluster (unchanged)',
    pg_size_pretty(pg_total_relation_size('benchmark.sales_fact_pax_nocluster'));

\echo ''

-- =============================================
-- Analyze All Tables
-- =============================================

\echo 'Running ANALYZE on all table variants...'
\echo ''

ANALYZE benchmark.sales_fact_ao;
\echo '  ✓ sales_fact_ao analyzed'

ANALYZE benchmark.sales_fact_aoco;
\echo '  ✓ sales_fact_aoco analyzed'

ANALYZE benchmark.sales_fact_pax;
\echo '  ✓ sales_fact_pax analyzed'

ANALYZE benchmark.sales_fact_pax_nocluster;
\echo '  ✓ sales_fact_pax_nocluster analyzed'

\echo ''

-- =============================================
-- Final Size Comparison
-- =============================================

\echo 'Final storage comparison:'
\echo ''

WITH storage_stats AS (
    SELECT 'AO' AS variant,
           pg_total_relation_size('benchmark.sales_fact_ao') AS size_bytes,
           1 AS sort_order
    UNION ALL
    SELECT 'AOCO',
           pg_total_relation_size('benchmark.sales_fact_aoco'),
           2
    UNION ALL
    SELECT 'PAX (clustered)',
           pg_total_relation_size('benchmark.sales_fact_pax'),
           3
    UNION ALL
    SELECT 'PAX (no-cluster)',
           pg_total_relation_size('benchmark.sales_fact_pax_nocluster'),
           4
)
SELECT variant,
       pg_size_pretty(size_bytes) AS size,
       ROUND(100.0 * size_bytes /
             (SELECT size_bytes FROM storage_stats WHERE variant = 'AOCO'), 2)
       AS pct_of_aoco
FROM storage_stats
ORDER BY sort_order;

\timing off

\echo ''
\echo '================================================'
\echo 'Optimization complete!'
\echo '================================================'
\echo ''
\echo 'PAX table is now:'
\echo '  • Z-order clustered on (sale_date, region)'
\echo '  • Optimized with sparse filtering'
\echo '  • Ready for benchmark queries'
\echo ''
\echo 'Next: Phase 5 - Run benchmark queries'
