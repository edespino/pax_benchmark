--
-- Phase 7: PAX Internal Statistics Inspection
-- Examines PAX auxiliary tables, file metadata, and statistics
--

\echo '================================================'
\echo 'PAX Benchmark - Phase 7: Internal Inspection'
\echo '================================================'
\echo ''

-- =============================================
-- Find PAX Auxiliary Tables
-- =============================================

\echo 'PAX Auxiliary Tables (Metadata Storage):'
\echo ''
\echo 'PAX stores file-level metadata in auxiliary tables with naming pattern:'
\echo '  pg_pax_<table_oid> or pax_<table_oid>_aux'
\echo ''

SELECT
    n.nspname AS schema,
    c.relname AS table_name,
    c.oid AS table_oid,
    'pg_pax_' || c.oid::text AS expected_aux_table,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'benchmark'
  AND c.relname LIKE 'sales_fact_pax%'
ORDER BY c.relname;

\echo ''

-- =============================================
-- Check PAX Access Method
-- =============================================

\echo 'Verify PAX Access Method:'
\echo ''

SELECT
    c.relname AS table_name,
    am.amname AS access_method,
    CASE am.amname
        WHEN 'pax' THEN '✅ PAX storage'
        WHEN 'ao_row' THEN 'AO row-oriented'
        WHEN 'ao_column' THEN 'AOCO column-oriented'
        WHEN 'heap' THEN 'Standard heap storage'
        ELSE am.amname
    END AS storage_type
FROM pg_class c
JOIN pg_am am ON c.relam = am.oid
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'benchmark')
  AND c.relname LIKE 'sales_fact_%'
ORDER BY c.relname;

\echo ''

-- =============================================
-- Column-Level Statistics (for Bloom Filter Analysis)
-- =============================================

\echo 'Column Statistics (Cardinality Analysis):'
\echo ''
\echo 'High n_distinct (>1000) → Good bloom filter candidates'
\echo 'Low n_distinct (<100)   → Better for minmax statistics'
\echo ''

SELECT
    schemaname,
    tablename,
    attname AS column_name,
    n_distinct,
    CASE
        WHEN n_distinct >= 1000 THEN '✅ HIGH - Excellent for bloom filters'
        WHEN n_distinct >= 100 THEN '🟡 MEDIUM - Consider bloom filters'
        WHEN n_distinct >= 10 THEN '🟠 LOW - Use minmax instead'
        ELSE '❌ VERY LOW - RLE compression candidate'
    END AS bloom_filter_suitability,
    null_frac * 100 AS null_percent,
    avg_width AS avg_bytes
FROM pg_stats
WHERE schemaname = 'benchmark'
  AND tablename = 'sales_fact_pax'
  AND attname IN (
      'transaction_hash', 'customer_id', 'product_id',
      'region', 'country', 'sales_channel', 'order_status'
  )
ORDER BY n_distinct DESC NULLS LAST;

\echo ''

-- =============================================
-- Table Reloptions (PAX Configuration)
-- =============================================

\echo 'PAX Table Configuration (Reloptions):'
\echo ''

SELECT
    c.relname AS table_name,
    unnest(c.reloptions) AS option
FROM pg_class c
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'benchmark')
  AND c.relname LIKE 'sales_fact_pax%'
ORDER BY c.relname, option;

\echo ''

-- =============================================
-- Compression Ratio Comparison
-- =============================================

\echo 'Compression Effectiveness:'
\echo ''

WITH table_stats AS (
    SELECT
        relname AS table_name,
        reltuples::bigint AS row_count_estimate,
        pg_total_relation_size(c.oid) AS compressed_bytes,
        -- Estimate uncompressed: rows × avg_row_width
        (SELECT SUM(avg_width) FROM pg_stats WHERE schemaname = 'benchmark' AND tablename = c.relname) AS avg_row_width
    FROM pg_class c
    WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'benchmark')
      AND c.relname LIKE 'sales_fact_%'
)
SELECT
    table_name,
    row_count_estimate AS rows,
    pg_size_pretty(compressed_bytes) AS compressed_size,
    pg_size_pretty(row_count_estimate * COALESCE(avg_row_width, 600)) AS estimated_uncompressed,
    ROUND(
        (row_count_estimate * COALESCE(avg_row_width, 600))::numeric /
        NULLIF(compressed_bytes, 0),
        2
    ) AS compression_ratio
FROM table_stats
ORDER BY table_name;

\echo ''

-- =============================================
-- PAX GUC Settings
-- =============================================

\echo 'Current PAX GUC Configuration:'
\echo ''

SELECT
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE 'pax.%'
   OR name LIKE 'pax_%'
ORDER BY name;

\echo ''

-- =============================================
-- File Count Estimation
-- =============================================

\echo 'Estimated PAX File Count:'
\echo ''
\echo 'PAX creates micro-partitions (files) based on:'
\echo '  - pax.max_tuples_per_file (default: 1,310,720)'
\echo '  - pax.max_size_per_file (default: 64MB)'
\echo ''

WITH file_estimate AS (
    SELECT
        c.relname AS table_name,
        c.reltuples::bigint AS row_count,
        (SELECT setting::bigint FROM pg_settings WHERE name = 'pax.max_tuples_per_file' OR name = 'pax_max_tuples_per_file' LIMIT 1) AS max_tuples_per_file,
        pg_total_relation_size(c.oid) AS total_bytes,
        (SELECT setting::bigint * 1024 * 1024 FROM pg_settings WHERE name = 'pax.max_size_per_file' OR name = 'pax_max_size_per_file' LIMIT 1) AS max_file_bytes
    FROM pg_class c
    WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'benchmark')
      AND c.relname LIKE 'sales_fact_pax%'
)
SELECT
    table_name,
    row_count AS total_rows,
    GREATEST(
        CEIL(row_count::numeric / NULLIF(max_tuples_per_file, 0)),
        CEIL(total_bytes::numeric / NULLIF(max_file_bytes, 0))
    )::bigint AS estimated_file_count,
    max_tuples_per_file AS tuples_per_file_limit,
    pg_size_pretty(max_file_bytes) AS size_per_file_limit
FROM file_estimate
ORDER BY table_name;

\echo ''

-- =============================================
-- Recommendations
-- =============================================

\echo 'Analysis Summary & Recommendations:'
\echo ''
\echo '1. Check "Column Statistics" for bloom filter effectiveness'
\echo '   → High cardinality (>1000) justifies bloom filters'
\echo '   → Low cardinality (<100) wastes memory'
\echo ''
\echo '2. Review "PAX Table Configuration" for current settings'
\echo '   → minmax_columns: Should include all filterable columns'
\echo '   → bloomfilter_columns: Only high-cardinality columns'
\echo ''
\echo '3. Validate "Compression Ratio"'
\echo '   → PAX should be competitive with AOCO (8x+)'
\echo '   → Lower ratios may indicate clustering bloat'
\echo ''
\echo '4. Estimate "File Count" for pruning potential'
\echo '   → More files = more granular pruning'
\echo '   → Fewer files = less overhead'
\echo ''

\echo ''
\echo '================================================'
\echo 'Inspection Complete'
\echo '================================================'
\echo ''
