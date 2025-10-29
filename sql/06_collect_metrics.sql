--
-- Phase 6: Metrics Collection
-- Gather comprehensive performance and storage metrics
--

\echo '================================================'
\echo 'PAX Benchmark - Metrics Collection'
\echo '================================================'
\echo ''

-- =============================================
-- Storage Size Comparison
-- =============================================

\echo 'STORAGE SIZE COMPARISON'
\echo '======================='
\echo ''

WITH storage_stats AS (
    SELECT 'AO' AS variant,
           pg_total_relation_size('benchmark.sales_fact_ao') AS total_size,
           pg_relation_size('benchmark.sales_fact_ao') AS table_size,
           pg_total_relation_size('benchmark.sales_fact_ao') -
           pg_relation_size('benchmark.sales_fact_ao') AS index_size,
           1 AS sort_order
    UNION ALL
    SELECT 'AOCO',
           pg_total_relation_size('benchmark.sales_fact_aoco'),
           pg_relation_size('benchmark.sales_fact_aoco'),
           pg_total_relation_size('benchmark.sales_fact_aoco') -
           pg_relation_size('benchmark.sales_fact_aoco'),
           2
    UNION ALL
    SELECT 'PAX (clustered)',
           pg_total_relation_size('benchmark.sales_fact_pax'),
           pg_relation_size('benchmark.sales_fact_pax'),
           pg_total_relation_size('benchmark.sales_fact_pax') -
           pg_relation_size('benchmark.sales_fact_pax'),
           3
    UNION ALL
    SELECT 'PAX (no-cluster)',
           pg_total_relation_size('benchmark.sales_fact_pax_nocluster'),
           pg_relation_size('benchmark.sales_fact_pax_nocluster'),
           pg_total_relation_size('benchmark.sales_fact_pax_nocluster') -
           pg_relation_size('benchmark.sales_fact_pax_nocluster'),
           4
),
base AS (
    SELECT total_size AS aoco_size
    FROM storage_stats
    WHERE variant = 'AOCO'
)
SELECT s.variant,
       pg_size_pretty(s.total_size) AS total_size,
       pg_size_pretty(s.table_size) AS table_size,
       pg_size_pretty(s.index_size) AS indexes,
       ROUND(100.0 * s.total_size / b.aoco_size, 2) AS pct_of_aoco,
       CASE
           WHEN s.total_size < b.aoco_size
           THEN ROUND(100.0 * (b.aoco_size - s.total_size) / b.aoco_size, 2)
           ELSE 0
       END AS savings_pct
FROM storage_stats s, base b
ORDER BY s.sort_order;

\echo ''

-- =============================================
-- PAX Micro-Partition Statistics
-- NOTE: get_pax_aux_table() not available in this PAX version
-- =============================================

\echo 'PAX MICRO-PARTITION DETAILS'
\echo '==========================='
\echo ''
\echo '  (Detailed PAX introspection not available in this version)'
\echo ''

-- =============================================
-- Row Count Verification
-- =============================================

\echo 'ROW COUNT VERIFICATION'
\echo '======================'
\echo ''

SELECT 'AO' AS variant, COUNT(*) AS row_count FROM benchmark.sales_fact_ao
UNION ALL
SELECT 'AOCO', COUNT(*) FROM benchmark.sales_fact_aoco
UNION ALL
SELECT 'PAX (clustered)', COUNT(*) FROM benchmark.sales_fact_pax
UNION ALL
SELECT 'PAX (no-cluster)', COUNT(*) FROM benchmark.sales_fact_pax_nocluster
ORDER BY variant;

\echo ''

-- =============================================
-- Compression Ratio by Variant
-- =============================================

\echo 'COMPRESSION ANALYSIS'
\echo '===================='
\echo ''

WITH raw_estimate AS (
    -- Estimate uncompressed size based on column types and actual row count
    SELECT ((SELECT COUNT(*) FROM benchmark.sales_fact_pax)::BIGINT * (
        8 +   -- DATE (sale_date)
        8 +   -- TIMESTAMP (sale_timestamp)
        8 +   -- BIGINT (order_id)
        4 +   -- INTEGER (customer_id)
        4 +   -- INTEGER (product_id)
        4 +   -- INTEGER (quantity)
        16 +  -- NUMERIC(12,2) (unit_price)
        8 +   -- NUMERIC(5,2) (discount_pct, with nulls)
        16 +  -- NUMERIC(12,2) (tax_amount)
        16 +  -- NUMERIC(10,2) (shipping_cost)
        16 +  -- NUMERIC(14,2) (total_amount)
        50 +  -- VARCHAR(50) region
        50 +  -- VARCHAR(50) country
        20 +  -- VARCHAR(20) sales_channel
        20 +  -- VARCHAR(20) order_status
        30 +  -- VARCHAR(30) payment_method
        100 + -- VARCHAR(100) product_category
        50 +  -- VARCHAR(50) customer_segment
        50 +  -- VARCHAR(50) promo_code
        1 +   -- CHAR(1) priority
        1 +   -- BOOLEAN is_return
        50 +  -- TEXT return_reason (sparse)
        50 +  -- TEXT special_notes (sparse)
        64    -- VARCHAR(64) transaction_hash
    ))::BIGINT AS estimated_raw_bytes
),
compressed AS (
    SELECT 'AO' AS variant,
           pg_total_relation_size('benchmark.sales_fact_ao') AS compressed_bytes,
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
SELECT c.variant,
       pg_size_pretty(r.estimated_raw_bytes) AS est_uncompressed,
       pg_size_pretty(c.compressed_bytes) AS compressed,
       ROUND(r.estimated_raw_bytes::NUMERIC / c.compressed_bytes, 2) AS compression_ratio
FROM compressed c, raw_estimate r
ORDER BY c.sort_order;

\echo ''

-- =============================================
-- Sample Query Performance Snapshot
-- Run a simple query on each variant for comparison
-- =============================================

\echo 'QUICK PERFORMANCE SAMPLE'
\echo '========================'
\echo 'Running identical query on each variant...'
\echo ''

\timing on

\echo '--- AO Variant ---'
SELECT COUNT(*), SUM(total_amount)
FROM benchmark.sales_fact_ao
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region = 'North America';

\echo ''
\echo '--- AOCO Variant ---'
SELECT COUNT(*), SUM(total_amount)
FROM benchmark.sales_fact_aoco
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region = 'North America';

\echo ''
\echo '--- PAX Clustered (with sparse filtering) ---'
SET pax.enable_sparse_filter = on;
SELECT COUNT(*), SUM(total_amount)
FROM benchmark.sales_fact_pax
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region = 'North America';

\echo ''
\echo '--- PAX No-Cluster (sparse filtering, no Z-order) ---'
SELECT COUNT(*), SUM(total_amount)
FROM benchmark.sales_fact_pax_nocluster
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region = 'North America';

\timing off

\echo ''
\echo '================================================'
\echo 'Metrics collection complete!'
\echo 'Use parse_explain_results.py to analyze query logs'
\echo '================================================'
