--
-- Sample Query Test - Compare AO vs AOCO vs PAX
--

\echo '================================================'
\echo 'Sample Query Comparison Test'
\echo '================================================'
\echo ''

SET pax.enable_sparse_filter = on;

\timing on

-- =======================================================
-- Q1: Sparse Filtering Test - Date Range
-- =======================================================

\echo '---------- Q1: Selective Date Range ----------'
\echo ''

\echo 'Q1 - AO (baseline):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_ao
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo 'Q1 - AOCO (column-oriented):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_aoco
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo 'Q1 - PAX clustered (with sparse filtering):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_pax
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo 'Q1 - PAX no-cluster (sparse filtering, no Z-order):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_pax_nocluster
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''
\echo ''

-- =======================================================
-- Q2: Bloom Filter Test - Region IN Clause
-- =======================================================

\echo '---------- Q2: Bloom Filter Test ----------'
\echo ''

\echo 'Q2 - AO (baseline):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       AVG(total_amount) AS avg_order_value,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_ao
WHERE region IN ('North America', 'Europe')
  AND sale_date >= '2022-01-01'
GROUP BY region;

\echo ''
\echo 'Q2 - AOCO (column-oriented):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       AVG(total_amount) AS avg_order_value,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_aoco
WHERE region IN ('North America', 'Europe')
  AND sale_date >= '2022-01-01'
GROUP BY region;

\echo ''
\echo 'Q2 - PAX clustered (with bloom filters):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       AVG(total_amount) AS avg_order_value,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_pax
WHERE region IN ('North America', 'Europe')
  AND sale_date >= '2022-01-01'
GROUP BY region;

\echo ''
\echo 'Q2 - PAX no-cluster (bloom filters, no Z-order):'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       AVG(total_amount) AS avg_order_value,
       COUNT(*) AS order_count
FROM benchmark.sales_fact_pax_nocluster
WHERE region IN ('North America', 'Europe')
  AND sale_date >= '2022-01-01'
GROUP BY region;

\timing off

\echo ''
\echo '================================================'
\echo 'Sample queries complete!'
\echo '================================================'
