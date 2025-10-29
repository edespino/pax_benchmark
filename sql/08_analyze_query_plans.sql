--
-- Phase 8: Query Plan Analysis
-- Detailed EXPLAIN ANALYZE to investigate file-level pruning effectiveness
--

\echo '================================================'
\echo 'PAX Benchmark - Phase 8: Query Plan Analysis'
\echo '================================================'
\echo ''

-- =============================================
-- Enable Debug Logging (Optional)
-- =============================================

\echo 'Enabling detailed query analysis...'
\echo ''

-- Enable debug output for PAX (if supported)
SET client_min_messages = 'notice';  -- Keep at notice to avoid overwhelming output
-- SET pax.enable_debug = on;        -- Uncomment if available
-- SET pax.log_filter_tree = on;     -- Uncomment if available

-- =============================================
-- Q1: Selective Date Range (Sparse Filter Test)
-- =============================================

\echo '================================================'
\echo 'Q1: Selective Date Range (0.7% selectivity)'
\echo '================================================'
\echo ''
\echo 'Tests: Min/max statistics, file-level pruning'
\echo 'Expected: PAX should skip 99% of files with date range filter'
\echo ''

\timing on

\echo '---------- Q1 - AOCO (Baseline) ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_aoco
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo '---------- Q1 - PAX Clustered ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_pax
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo '---------- Q1 - PAX No-Cluster ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_pax_nocluster
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo 'Q1 Analysis Notes:'
\echo '  - Look for "Rows Removed by Filter" (high = pruning NOT working)'
\echo '  - Check "Buffers: shared read" (high = reading many files)'
\echo '  - Review "Executor Memory" (should be low with good pruning)'
\echo ''

-- =============================================
-- Q2: High-Cardinality Bloom Filter Test
-- =============================================

\echo '================================================'
\echo 'Q2: High-Cardinality Bloom Filter Test'
\echo '================================================'
\echo ''
\echo 'Tests: Bloom filters on transaction_hash, customer_id, product_id'
\echo 'Expected: PAX should skip files not containing these high-cardinality values'
\echo ''

\echo '---------- Q2 - AOCO (Baseline) ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT COUNT(*) AS match_count,
       AVG(total_amount) AS avg_amount
FROM benchmark.sales_fact_aoco
WHERE customer_id IN (1000, 5000, 10000, 50000, 100000)
  AND sale_date >= '2023-01-01';

\echo ''
\echo '---------- Q2 - PAX Clustered ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT COUNT(*) AS match_count,
       AVG(total_amount) AS avg_amount
FROM benchmark.sales_fact_pax
WHERE customer_id IN (1000, 5000, 10000, 50000, 100000)
  AND sale_date >= '2023-01-01';

\echo ''
\echo '---------- Q2 - PAX No-Cluster ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT COUNT(*) AS match_count,
       AVG(total_amount) AS avg_amount
FROM benchmark.sales_fact_pax_nocluster
WHERE customer_id IN (1000, 5000, 10000, 50000, 100000)
  AND sale_date >= '2023-01-01';

\echo ''
\echo 'Q2 Analysis Notes:'
\echo '  - Bloom filters should eliminate files without matching customer_ids'
\echo '  - "Rows Removed by Filter" should be minimal if bloom filters work'
\echo '  - Compare buffer reads vs AOCO baseline'
\echo ''

-- =============================================
-- Q3: Multi-Dimensional Z-Order Test
-- =============================================

\echo '================================================'
\echo 'Q3: Multi-Dimensional Query (Z-Order Benefit)'
\echo '================================================'
\echo ''
\echo 'Tests: Z-order clustering on (sale_date, region)'
\echo 'Expected: PAX clustered should outperform PAX no-cluster'
\echo ''

\echo '---------- Q3 - AOCO (Baseline) ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT region,
       COUNT(*) AS orders,
       SUM(total_amount) AS revenue
FROM benchmark.sales_fact_aoco
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region IN ('North America', 'Europe')
GROUP BY region;

\echo ''
\echo '---------- Q3 - PAX Clustered (Z-Order) ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT region,
       COUNT(*) AS orders,
       SUM(total_amount) AS revenue
FROM benchmark.sales_fact_pax
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region IN ('North America', 'Europe')
GROUP BY region;

\echo ''
\echo '---------- Q3 - PAX No-Cluster ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT region,
       COUNT(*) AS orders,
       SUM(total_amount) AS revenue
FROM benchmark.sales_fact_pax_nocluster
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31'
  AND region IN ('North America', 'Europe')
GROUP BY region;

\echo ''
\echo 'Q3 Analysis Notes:'
\echo '  - Z-order clustering should co-locate date+region'
\echo '  - PAX clustered should filter fewer rows than no-cluster'
\echo '  - Look for execution time difference between PAX variants'
\echo ''

-- =============================================
-- Q4: Very Selective Query (Ultimate Pruning Test)
-- =============================================

\echo '================================================'
\echo 'Q4: Very Selective Query (<0.01% selectivity)'
\echo '================================================'
\echo ''
\echo 'Tests: Maximum file pruning potential'
\echo 'Expected: PAX should skip 99.9% of files'
\echo ''

\echo '---------- Q4 - AOCO (Baseline) ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT *
FROM benchmark.sales_fact_aoco
WHERE sale_date = '2023-01-15'
  AND region = 'North America'
  AND order_status = 'Delivered'
  AND customer_id BETWEEN 1000 AND 2000
LIMIT 100;

\echo ''
\echo '---------- Q4 - PAX Clustered ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT *
FROM benchmark.sales_fact_pax
WHERE sale_date = '2023-01-15'
  AND region = 'North America'
  AND order_status = 'Delivered'
  AND customer_id BETWEEN 1000 AND 2000
LIMIT 100;

\echo ''
\echo '---------- Q4 - PAX No-Cluster ----------'
EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS, TIMING, SUMMARY)
SELECT *
FROM benchmark.sales_fact_pax_nocluster
WHERE sale_date = '2023-01-15'
  AND region = 'North America'
  AND order_status = 'Delivered'
  AND customer_id BETWEEN 1000 AND 2000
LIMIT 100;

\echo ''
\echo 'Q4 Analysis Notes:'
\echo '  - Multiple minmax-eligible columns (date, region, status, customer_id)'
\echo '  - Should see dramatic file skipping if pruning works'
\echo '  - LIMIT should enable early termination'
\echo ''

\timing off

-- =============================================
-- Cleanup
-- =============================================

-- Reset settings
SET client_min_messages = 'notice';
-- SET pax.enable_debug = off;
-- SET pax.log_filter_tree = off;

-- =============================================
-- Summary & Interpretation Guide
-- =============================================

\echo ''
\echo '================================================'
\echo 'Query Plan Analysis Summary'
\echo '================================================'
\echo ''
\echo 'Key Metrics to Compare:'
\echo ''
\echo '1. Execution Time'
\echo '   → PAX should match or beat AOCO on selective queries'
\echo '   → If PAX is slower, file pruning may not be working'
\echo ''
\echo '2. Rows Removed by Filter'
\echo '   → Low = Good (filtering at file level before read)'
\echo '   → High = Bad (reading files then filtering rows)'
\echo ''
\echo '3. Buffers: shared read'
\echo '   → Indicates I/O volume'
\echo '   → PAX should read fewer buffers with good pruning'
\echo ''
\echo '4. Executor Memory'
\echo '   → PAX should use similar or less memory than AOCO'
\echo '   → High memory (>10MB) may indicate clustering issue'
\echo ''
\echo '5. Planning Time vs Execution Time'
\echo '   → PAX planning may be slightly higher (statistics lookup)'
\echo '   → But execution should be faster (skip files)'
\echo ''
\echo 'Expected Results (if PAX working optimally):'
\echo '  Q1: PAX 2-3x faster than AOCO (date range pruning)'
\echo '  Q2: PAX 1.5-2x faster (bloom filter pruning)'
\echo '  Q3: PAX clustered 2-5x faster than no-cluster (Z-order)'
\echo '  Q4: PAX 5-10x faster (multi-column pruning)'
\echo ''
\echo 'If PAX is SLOWER than AOCO:'
\echo '  → File-level pruning is not working'
\echo '  → Check: pax.enable_sparse_filter = on'
\echo '  → Verify: minmax_columns and bloomfilter_columns configured'
\echo '  → Issue: Predicate pushdown may be disabled in code'
\echo ''
\echo '================================================'
\echo 'Analysis Complete'
\echo '================================================'
\echo ''
