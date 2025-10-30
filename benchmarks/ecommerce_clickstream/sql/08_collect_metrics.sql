--
-- Phase 8: Collect Metrics
-- Storage comparison and compression effectiveness
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 8: Collect Metrics'
\echo '===================================================='
\echo ''

\echo 'Storage comparison across all 4 variants:'
\echo ''

SELECT
    CASE
        WHEN tablename = 'clickstream_ao' THEN '1. AO'
        WHEN tablename = 'clickstream_aoco' THEN '2. AOCO'
        WHEN tablename = 'clickstream_pax_nocluster' THEN '3. PAX (no-cluster)'
        WHEN tablename = 'clickstream_pax' THEN '4. PAX (clustered)'
    END AS variant,
    pg_size_pretty(pg_relation_size('ecommerce.' || tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size('ecommerce.' || tablename)) AS indexes_size,
    pg_size_pretty(pg_total_relation_size('ecommerce.' || tablename)) AS total_size
FROM pg_tables
WHERE schemaname = 'ecommerce'
  AND tablename LIKE 'clickstream_%'
ORDER BY pg_total_relation_size('ecommerce.' || tablename) DESC;

\echo ''
\echo 'PAX configuration overhead analysis:'
\echo ''

WITH sizes AS (
    SELECT
        pg_total_relation_size('ecommerce.clickstream_aoco') AS aoco_size,
        pg_total_relation_size('ecommerce.clickstream_pax_nocluster') AS pax_nc_size,
        pg_total_relation_size('ecommerce.clickstream_pax') AS pax_c_size
)
SELECT
    'PAX (no-cluster) vs AOCO' AS comparison,
    pg_size_pretty(pax_nc_size) AS pax_size,
    pg_size_pretty(aoco_size) AS baseline_size,
    pg_size_pretty(pax_nc_size - aoco_size) AS overhead,
    ROUND(100.0 * (pax_nc_size::NUMERIC / aoco_size - 1), 1) || '%' AS overhead_pct,
    CASE
        WHEN pax_nc_size::NUMERIC / aoco_size <= 1.10 THEN '✅ Excellent (<10%)'
        WHEN pax_nc_size::NUMERIC / aoco_size <= 1.20 THEN '✅ Good (10-20%)'
        WHEN pax_nc_size::NUMERIC / aoco_size <= 1.30 THEN '🟠 Acceptable (20-30%)'
        ELSE '❌ High (>30%)'
    END AS assessment
FROM sizes
UNION ALL
SELECT
    'PAX (clustered) vs no-cluster',
    pg_size_pretty(pax_c_size),
    pg_size_pretty(pax_nc_size),
    pg_size_pretty(pax_c_size - pax_nc_size),
    ROUND(100.0 * (pax_c_size::NUMERIC / pax_nc_size - 1), 1) || '%',
    CASE
        WHEN pax_c_size::NUMERIC / pax_nc_size <= 1.10 THEN '✅ Minimal (<10%)'
        WHEN pax_c_size::NUMERIC / pax_nc_size <= 1.30 THEN '✅ Acceptable (10-30%)'
        WHEN pax_c_size::NUMERIC / pax_nc_size <= 1.50 THEN '🟠 Moderate (30-50%)'
        ELSE '❌ High (>50%)'
    END
FROM sizes
UNION ALL
SELECT
    'PAX (clustered) vs AOCO',
    pg_size_pretty(pax_c_size),
    pg_size_pretty(aoco_size),
    pg_size_pretty(pax_c_size - aoco_size),
    ROUND(100.0 * (pax_c_size::NUMERIC / aoco_size - 1), 1) || '%',
    CASE
        WHEN pax_c_size::NUMERIC / aoco_size <= 1.20 THEN '✅ Good (<20%)'
        WHEN pax_c_size::NUMERIC / aoco_size <= 1.40 THEN '🟠 Acceptable (20-40%)'
        ELSE '❌ High (>40%)'
    END
FROM sizes;

\echo ''
\echo 'Sparse field efficiency (PAX advantage):'
\echo ''

SELECT
    'product_id' AS sparse_column,
    ROUND(100.0 * COUNT(*) FILTER (WHERE product_id IS NULL) / COUNT(*), 1) || '%' AS null_percentage,
    '~60% expected' AS target,
    CASE
        WHEN 100.0 * COUNT(*) FILTER (WHERE product_id IS NULL) / COUNT(*) BETWEEN 55 AND 65
        THEN '✅ Expected sparsity'
        ELSE '⚠️  Different than expected'
    END AS sparsity_rating
FROM ecommerce.clickstream_aoco
UNION ALL
SELECT
    'user_id',
    ROUND(100.0 * COUNT(*) FILTER (WHERE user_id IS NULL) / COUNT(*), 1) || '%',
    '~70% expected',
    CASE
        WHEN 100.0 * COUNT(*) FILTER (WHERE user_id IS NULL) / COUNT(*) BETWEEN 65 AND 75
        THEN '✅ Expected sparsity'
        ELSE '⚠️  Different than expected'
    END
FROM ecommerce.clickstream_aoco
UNION ALL
SELECT
    'utm_campaign',
    ROUND(100.0 * COUNT(*) FILTER (WHERE utm_campaign IS NULL) / COUNT(*), 1) || '%',
    '~40% expected',
    CASE
        WHEN 100.0 * COUNT(*) FILTER (WHERE utm_campaign IS NULL) / COUNT(*) BETWEEN 35 AND 45
        THEN '✅ Expected sparsity'
        ELSE '⚠️  Different than expected'
    END
FROM ecommerce.clickstream_aoco;

\echo ''
\echo '===================================================='
\echo 'Metrics collection complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 9 - Validate results'
\echo 'Run: psql -f sql/09_validate_results.sql'
\echo ''
