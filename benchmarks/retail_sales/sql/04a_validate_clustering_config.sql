--
-- Phase 4a: Validate Clustering Configuration
-- Checks memory settings and calculates requirements before clustering
--

\echo '================================================'
\echo 'PAX Benchmark - Phase 4a: Validate Clustering'
\echo '================================================'
\echo ''

-- =============================================
-- Show Current Memory Configuration
-- =============================================

\echo 'Current PostgreSQL Memory Settings:'
\echo ''

SELECT
    name,
    setting,
    unit,
    CASE
        WHEN unit = 'kB' THEN pg_size_pretty(setting::bigint * 1024)
        WHEN unit = 'MB' THEN pg_size_pretty(setting::bigint * 1024 * 1024)
        WHEN unit = '8kB' THEN pg_size_pretty(setting::bigint * 8192)
        ELSE setting || ' ' || COALESCE(unit, '')
    END AS pretty_value
FROM pg_settings
WHERE name IN (
    'maintenance_work_mem',
    'work_mem',
    'shared_buffers',
    'effective_cache_size'
)
ORDER BY name;

\echo ''

-- =============================================
-- Calculate Required Memory for Clustering
-- =============================================

\echo 'Memory Requirements for Z-Order Clustering:'
\echo ''

WITH pax_table_stats AS (
    SELECT
        'sales_fact_pax' AS table_name,
        COUNT(*) AS row_count,
        pg_relation_size('benchmark.sales_fact_pax') AS table_bytes,
        COUNT(*) * 600 AS estimated_bytes  -- ~600 bytes/row average
    FROM benchmark.sales_fact_pax
),
memory_config AS (
    SELECT
        CASE
            WHEN unit = 'kB' THEN setting::bigint * 1024
            WHEN unit = 'MB' THEN setting::bigint * 1024 * 1024
            WHEN unit = '8kB' THEN setting::bigint * 8192
            ELSE setting::bigint
        END AS maintenance_work_mem_bytes
    FROM pg_settings
    WHERE name = 'maintenance_work_mem'
)
SELECT
    pts.table_name,
    pts.row_count,
    pg_size_pretty(pts.table_bytes) AS current_table_size,
    pg_size_pretty(pts.estimated_bytes) AS estimated_uncompressed_size,
    pg_size_pretty(pts.estimated_bytes * 2) AS ideal_clustering_memory,
    pg_size_pretty(mc.maintenance_work_mem_bytes) AS configured_memory,
    CASE
        WHEN mc.maintenance_work_mem_bytes >= pts.estimated_bytes * 2
        THEN '✅ SUFFICIENT - Clustering will run in-memory'
        WHEN mc.maintenance_work_mem_bytes >= pts.estimated_bytes * 0.5
        THEN '⚠️  MARGINAL - Some spilling expected, should be OK'
        WHEN mc.maintenance_work_mem_bytes >= pts.estimated_bytes * 0.1
        THEN '❌ INSUFFICIENT - Heavy spilling, may cause storage bloat'
        ELSE '❌ CRITICAL - Severely insufficient, WILL cause 2-3x bloat'
    END AS memory_assessment,
    CASE
        WHEN mc.maintenance_work_mem_bytes < pts.estimated_bytes * 2
        THEN pg_size_pretty(pts.estimated_bytes * 2)
        ELSE 'Current setting is adequate'
    END AS recommended_setting
FROM pax_table_stats pts, memory_config mc;

\echo ''

-- =============================================
-- Recommendations
-- =============================================

\echo 'Memory Configuration Recommendations:'
\echo ''
\echo 'For optimal clustering without storage bloat:'
\echo ''

WITH pax_table_stats AS (
    SELECT COUNT(*) AS row_count FROM benchmark.sales_fact_pax
)
SELECT
    CASE
        WHEN row_count <= 1000000 THEN '  Small dataset (< 1M rows):    SET maintenance_work_mem = ''512MB'';'
        WHEN row_count <= 10000000 THEN '  Medium dataset (< 10M rows):  SET maintenance_work_mem = ''2GB'';'
        WHEN row_count <= 50000000 THEN '  Large dataset (< 50M rows):   SET maintenance_work_mem = ''8GB'';'
        WHEN row_count <= 200000000 THEN '  XLarge dataset (< 200M rows): SET maintenance_work_mem = ''32GB'';'
        ELSE '  XXLarge dataset (200M+ rows): SET maintenance_work_mem = ''64GB'';'
    END AS recommendation
FROM pax_table_stats;

\echo ''
\echo 'To apply recommended setting:'
\echo '  1. Run: SET maintenance_work_mem = ''<recommended_value>'';'
\echo '  2. Then execute: CLUSTER benchmark.sales_fact_pax;'
\echo ''
\echo 'Or set permanently in postgresql.conf:'
\echo '  maintenance_work_mem = <recommended_value>'
\echo ''

-- =============================================
-- Check for Adequate Disk Space
-- =============================================

\echo 'Disk Space Assessment:'
\echo ''

WITH table_sizes AS (
    SELECT
        SUM(pg_total_relation_size('benchmark.' || tablename)) AS total_bytes
    FROM pg_tables
    WHERE schemaname = 'benchmark'
)
SELECT
    pg_size_pretty(total_bytes) AS current_benchmark_size,
    pg_size_pretty(total_bytes * 2) AS required_free_space,
    'Clustering may temporarily double storage usage' AS note
FROM table_sizes;

\echo ''
\echo '================================================'
\echo 'Validation Complete'
\echo '================================================'
\echo ''
\echo 'If memory assessment shows ❌ INSUFFICIENT:'
\echo '  → STOP and increase maintenance_work_mem before clustering'
\echo '  → Risk: Storage bloat (2-3x size increase)'
\echo ''
\echo 'If memory assessment shows ✅ SUFFICIENT:'
\echo '  → Proceed with sql/04_optimize_pax.sql'
\echo ''
