--
-- Phase 5: Complete Benchmark Query Suite
-- 20 queries across 7 categories to test PAX features
--
-- Usage: Run via run_full_benchmark.sh for proper timing and comparison
-- Or manually substitute TABLE_VARIANT with: sales_fact_ao, sales_fact_aoco, or sales_fact_pax
--

\echo '================================================'
\echo 'PAX Benchmark Query Suite'
\echo '================================================'
\echo ''

SET pax.enable_sparse_filter = on;
SET pax.enable_debug = on;
SET client_min_messages = LOG;

-- =======================================================
-- CATEGORY A: Sparse Filtering (Zone Maps / Min-Max Stats)
-- Tests: File pruning based on min/max statistics
-- =======================================================

\echo 'Category A: Sparse Filtering Tests'
\echo ''

-- Q1: Selective date range (tests min/max pruning on date)
\echo 'Q1: Selective date range aggregation'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT SUM(total_amount) AS revenue,
       AVG(quantity) AS avg_qty,
       COUNT(*) AS order_count
FROM benchmark.TABLE_VARIANT
WHERE sale_date BETWEEN '2023-01-01' AND '2023-01-31';

\echo ''

-- Q2: Multi-column range filter (compound filtering)
\echo 'Q2: Multi-column range with selective predicates'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS matching_orders,
       SUM(total_amount) AS revenue
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2022-06-01'
  AND total_amount > 5000
  AND quantity < 10;

\echo ''

-- Q3: Selective aggregation with grouping
\echo 'Q3: Selective aggregation with GROUP BY'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       sales_channel,
       SUM(total_amount) AS revenue,
       COUNT(*) AS orders,
       AVG(unit_price) AS avg_price
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2023-01-01'
  AND order_status = 'Delivered'
GROUP BY region, sales_channel
ORDER BY revenue DESC
LIMIT 20;

\echo ''

-- =======================================================
-- CATEGORY B: Bloom Filter Tests
-- Tests: Bloom filter effectiveness on high-cardinality columns
-- =======================================================

\echo 'Category B: Bloom Filter Tests'
\echo ''

-- Q4: IN clause on bloom-filtered column (region)
\echo 'Q4: IN clause with bloom filter (region)'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       AVG(total_amount) AS avg_order_value,
       COUNT(*) AS order_count
FROM benchmark.TABLE_VARIANT
WHERE region IN ('North America', 'Europe')
  AND sale_date >= '2022-01-01'
GROUP BY region;

\echo ''

-- Q5: Multiple bloom filter columns
\echo 'Q5: Multiple bloom filter predicates'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS matching_orders,
       SUM(total_amount) AS total_revenue
FROM benchmark.TABLE_VARIANT
WHERE country IN ('USA', 'Canada', 'UK', 'Germany')
  AND sales_channel = 'Online'
  AND order_status IN ('Shipped', 'Delivered')
  AND product_category IN ('Category_5', 'Category_10', 'Category_15');

\echo ''

-- Q6: Hash lookup with bloom filter
\echo 'Q6: Transaction hash lookup (bloom filter)'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS found_transactions,
       AVG(total_amount) AS avg_amount
FROM benchmark.TABLE_VARIANT
WHERE transaction_hash IN (
    SELECT md5(generate_series::TEXT)
    FROM generate_series(1000000, 1000100)
);

\echo ''

-- =======================================================
-- CATEGORY C: Z-Order Clustering Benefits
-- Tests: Multi-dimensional range queries on clustered dimensions
-- =======================================================

\echo 'Category C: Z-Order Clustering Tests'
\echo ''

-- Q7: Multi-dimensional range (clustered dimensions)
\echo 'Q7: Correlated date + region query'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT sale_date::DATE AS day,
       SUM(total_amount) AS daily_revenue,
       COUNT(*) AS order_count
FROM benchmark.TABLE_VARIANT
WHERE sale_date BETWEEN '2022-12-01' AND '2022-12-31'
  AND region = 'North America'
GROUP BY day
ORDER BY day;

\echo ''

-- Q8: Multiple regions with date range
\echo 'Q8: Multiple regions in date range'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT DATE_TRUNC('week', sale_date) AS week,
       region,
       SUM(total_amount) AS weekly_revenue,
       COUNT(*) AS order_count
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2023-01-01'
  AND region IN ('Asia Pacific', 'Europe')
GROUP BY week, region
ORDER BY week, region;

\echo ''

-- Q9: Time-series with regional aggregation
\echo 'Q9: Monthly time-series by region'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT DATE_TRUNC('month', sale_date) AS month,
       region,
       SUM(total_amount) AS revenue,
       AVG(unit_price) AS avg_price,
       COUNT(DISTINCT customer_id) AS unique_customers
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2022-01-01'
GROUP BY month, region
ORDER BY month, region;

\echo ''

-- =======================================================
-- CATEGORY D: Compression Efficiency (I/O Heavy)
-- Tests: Full scans and wide projections
-- =======================================================

\echo 'Category D: Compression & I/O Tests'
\echo ''

-- Q10: Full table scan with simple aggregation
\echo 'Q10: Full table aggregation'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS total_orders,
       SUM(total_amount) AS total_revenue,
       AVG(quantity) AS avg_quantity,
       MIN(sale_date) AS first_sale,
       MAX(sale_date) AS last_sale
FROM benchmark.TABLE_VARIANT;

\echo ''

-- Q11: Wide projection (many columns)
\echo 'Q11: Wide projection query'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT sale_date, order_id, customer_id, product_id,
       quantity, unit_price, total_amount,
       region, country, sales_channel,
       order_status, payment_method, product_category,
       customer_segment, priority
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2023-01-01'
LIMIT 100000;

\echo ''

-- Q12: Aggregation on encoded columns (RLE test)
\echo 'Q12: Aggregation on low-cardinality columns'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT priority,
       is_return,
       order_status,
       sales_channel,
       COUNT(*) AS order_count,
       SUM(total_amount) AS revenue,
       AVG(total_amount) AS avg_order_value
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2022-01-01'
GROUP BY priority, is_return, order_status, sales_channel
ORDER BY revenue DESC;

\echo ''

-- =======================================================
-- CATEGORY E: Complex Analytical Queries
-- Tests: Joins, window functions, subqueries
-- =======================================================

\echo 'Category E: Complex Analytics Tests'
\echo ''

-- Q13: Multi-table join with aggregation
\echo 'Q13: Fact-dimension join'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT c.segment AS customer_segment,
       p.category AS product_category,
       COUNT(f.order_id) AS orders,
       SUM(f.total_amount) AS revenue,
       AVG(f.unit_price) AS avg_price
FROM benchmark.TABLE_VARIANT f
JOIN benchmark.customers c ON f.customer_id = c.customer_id
JOIN benchmark.products p ON f.product_id = p.product_id
WHERE f.sale_date >= '2023-01-01'
GROUP BY c.segment, p.category
HAVING SUM(f.total_amount) > 100000
ORDER BY revenue DESC
LIMIT 50;

\echo ''

-- Q14: Window function (rolling average)
\echo 'Q14: Rolling average with window function'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT sale_date::DATE AS day,
       region,
       SUM(total_amount) AS daily_revenue,
       AVG(SUM(total_amount)) OVER (
           PARTITION BY region
           ORDER BY sale_date::DATE
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS rolling_7day_avg
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2023-01-01'
  AND sale_date < '2023-02-01'
GROUP BY day, region
ORDER BY region, day;

\echo ''

-- Q15: Correlated subquery
\echo 'Q15: Above-average orders by region'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT region,
       COUNT(*) AS high_value_orders,
       AVG(total_amount) AS avg_high_value
FROM benchmark.TABLE_VARIANT f1
WHERE total_amount > (
    SELECT AVG(total_amount)
    FROM benchmark.TABLE_VARIANT f2
    WHERE f2.region = f1.region
      AND f2.sale_date >= '2023-01-01'
)
AND f1.sale_date >= '2023-01-01'
GROUP BY region
ORDER BY high_value_orders DESC;

\echo ''

-- =======================================================
-- CATEGORY F: MVCC & Update Performance
-- Tests: Visimap and update efficiency
-- =======================================================

\echo 'Category F: MVCC Tests (Updates/Deletes)'
\echo ''

-- Q16: Selective update
\echo 'Q16: Selective update operation'
\echo 'Updating pending orders for a specific date...'
BEGIN;
UPDATE benchmark.TABLE_VARIANT
SET order_status = 'Cancelled'
WHERE sale_date = '2023-01-15'
  AND order_status = 'Pending';
ROLLBACK;  -- Don't actually commit for reproducibility

\echo ''

-- Q17: Query after hypothetical update (visimap test)
\echo 'Q17: Query with visibility filtering'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT order_status,
       COUNT(*) AS status_count,
       SUM(total_amount) AS revenue
FROM benchmark.TABLE_VARIANT
WHERE sale_date = '2023-01-15'
GROUP BY order_status;

\echo ''

-- Q18: Selective delete pattern
\echo 'Q18: Selective delete query pattern'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS deletable_rows
FROM benchmark.TABLE_VARIANT
WHERE is_return = true
  AND sale_date < '2020-06-01'
  AND return_reason IS NOT NULL;

\echo ''

-- =======================================================
-- CATEGORY G: Edge Cases
-- Tests: NULL handling, high cardinality
-- =======================================================

\echo 'Category G: Edge Cases'
\echo ''

-- Q19: NULL handling and sparse columns
\echo 'Q19: NULL analysis on sparse columns'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS total_orders,
       COUNT(discount_pct) AS orders_with_discount,
       COUNT(return_reason) AS orders_with_returns,
       COUNT(promo_code) AS orders_with_promo,
       AVG(COALESCE(discount_pct, 0)) AS avg_discount
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2023-01-01';

\echo ''

-- Q20: High cardinality GROUP BY
\echo 'Q20: High cardinality aggregation'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT transaction_hash,
       MIN(sale_date) AS first_seen,
       SUM(total_amount) AS total_value
FROM benchmark.TABLE_VARIANT
WHERE sale_date >= '2023-06-01'
GROUP BY transaction_hash
HAVING SUM(total_amount) > 10000
ORDER BY total_value DESC
LIMIT 100;

\echo ''
\echo '================================================'
\echo 'Query suite complete!'
\echo '================================================'
