--
-- Phase 7: Run Benchmark Queries
-- 12 queries testing PAX features across clickstream patterns
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 7: Run Queries'
\echo '===================================================='
\echo ''
\echo 'Running 12 queries (3 runs each for median calculation)...'
\echo ''

-- Substitute TABLE_VARIANT when running (clickstream_ao, clickstream_aoco, clickstream_pax, clickstream_pax_nocluster)

-- =====================================================
-- Category 1: Session Analysis (Bloom Filter Test)
-- =====================================================

\echo 'Q1: Full session journey (session_id bloom filter lookup)...'
SELECT COUNT(*), MIN(event_timestamp), MAX(event_timestamp), 
       string_agg(DISTINCT event_type, ',' ORDER BY event_type) AS journey
FROM ecommerce.TABLE_VARIANT
WHERE session_id = 'sess-0cc175b9c0f1b6a831c399e269772661'
GROUP BY session_id;

\echo 'Q2: User behavior across sessions (user_id bloom filter)...'
SELECT event_type, COUNT(*) AS event_count, 
       COUNT(DISTINCT session_id) AS session_count
FROM ecommerce.TABLE_VARIANT
WHERE user_id = 'user-0000012345'
GROUP BY event_type
ORDER BY event_count DESC;

-- =====================================================
-- Category 2: Funnel Analysis (Time + Event Filtering)
-- =====================================================

\echo 'Q3: Purchase conversion funnel (last 24 hours)...'
SELECT event_type, COUNT(*) AS events, 
       COUNT(DISTINCT session_id) AS sessions,
       ROUND(100.0 * COUNT(DISTINCT session_id) / 
             NULLIF((SELECT COUNT(DISTINCT session_id) 
                     FROM ecommerce.TABLE_VARIANT 
                     WHERE event_date >= CURRENT_DATE - 1), 0), 2) AS conversion_rate
FROM ecommerce.TABLE_VARIANT
WHERE event_date >= CURRENT_DATE - 1
  AND event_type IN ('page_view', 'product_view', 'add_to_cart', 'begin_checkout', 'purchase')
GROUP BY event_type
ORDER BY 
    CASE event_type
        WHEN 'page_view' THEN 1
        WHEN 'product_view' THEN 2
        WHEN 'add_to_cart' THEN 3
        WHEN 'begin_checkout' THEN 4
        WHEN 'purchase' THEN 5
    END;

\echo 'Q4: Cart abandonment rate (begin_checkout vs purchase)...'
SELECT 
    COUNT(DISTINCT CASE WHEN event_type = 'begin_checkout' THEN session_id END) AS checkout_sessions,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN session_id END) AS purchase_sessions,
    ROUND(100.0 * (COUNT(DISTINCT CASE WHEN event_type = 'begin_checkout' THEN session_id END) - 
                   COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN session_id END)) / 
          NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'begin_checkout' THEN session_id END), 0), 2) AS abandonment_rate
FROM ecommerce.TABLE_VARIANT
WHERE event_date >= CURRENT_DATE - 7;

-- =====================================================
-- Category 3: Product Analytics (Product Bloom Filter)
-- =====================================================

\echo 'Q5: Product view vs purchase rate (specific product)...'
SELECT product_id,
       COUNT(CASE WHEN event_type = 'product_view' THEN 1 END) AS views,
       COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS purchases,
       ROUND(100.0 * COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) / 
             NULLIF(COUNT(CASE WHEN event_type = 'product_view' THEN 1 END), 0), 2) AS conversion_rate
FROM ecommerce.TABLE_VARIANT
WHERE product_id = 'prod-00001234'
  AND event_date >= CURRENT_DATE - 7
GROUP BY product_id;

\echo 'Q6: Top products by category (minmax + sparse filtering)...'
SELECT product_category, COUNT(*) AS views, 
       COUNT(DISTINCT session_id) AS unique_viewers
FROM ecommerce.TABLE_VARIANT
WHERE event_type = 'product_view'
  AND product_category = 'Electronics'
  AND event_date >= CURRENT_DATE - 7
GROUP BY product_category;

-- =====================================================
-- Category 4: Real-time Dashboards (Recent Time Filtering)
-- =====================================================

\echo 'Q7: Last hour events by type (time-based filtering)...'
SELECT event_type, COUNT(*) AS event_count
FROM ecommerce.TABLE_VARIANT
WHERE event_timestamp >= NOW() - INTERVAL '1 hour'
GROUP BY event_type
ORDER BY event_count DESC;

\echo 'Q8: Active sessions in last 30 minutes...'
SELECT COUNT(DISTINCT session_id) AS active_sessions,
       AVG(time_on_page_seconds) AS avg_time_on_page
FROM ecommerce.TABLE_VARIANT
WHERE event_timestamp >= NOW() - INTERVAL '30 minutes';

-- =====================================================
-- Category 5: Marketing Attribution
-- =====================================================

\echo 'Q9: Campaign performance (utm_campaign + purchases)...'
SELECT utm_campaign, 
       COUNT(DISTINCT session_id) AS sessions,
       COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS purchases,
       ROUND(100.0 * COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) / 
             NULLIF(COUNT(DISTINCT session_id), 0), 2) AS conversion_rate
FROM ecommerce.TABLE_VARIANT
WHERE utm_campaign IS NOT NULL
  AND event_date >= CURRENT_DATE - 7
GROUP BY utm_campaign
ORDER BY purchases DESC
LIMIT 10;

\echo 'Q10: Channel ROI (utm_source + revenue estimate)...'
SELECT utm_source,
       COUNT(DISTINCT session_id) AS sessions,
       SUM(CASE WHEN event_type = 'purchase' THEN cart_value ELSE 0 END) AS revenue
FROM ecommerce.TABLE_VARIANT
WHERE event_date >= CURRENT_DATE - 7
GROUP BY utm_source
ORDER BY revenue DESC;

-- =====================================================
-- Category 6: Device & Geography Analysis
-- =====================================================

\echo 'Q11: Mobile vs desktop conversion (device_type minmax)...'
SELECT device_type,
       COUNT(*) AS events,
       COUNT(DISTINCT session_id) AS sessions,
       COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS purchases
FROM ecommerce.TABLE_VARIANT
WHERE event_date >= CURRENT_DATE - 7
GROUP BY device_type;

\echo 'Q12: Geographic patterns (country_code minmax)...'
SELECT country_code,
       COUNT(DISTINCT session_id) AS sessions,
       COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS purchases,
       ROUND(AVG(CASE WHEN cart_value IS NOT NULL THEN cart_value END), 2) AS avg_cart_value
FROM ecommerce.TABLE_VARIANT
WHERE event_date >= CURRENT_DATE - 7
  AND country_code IN ('US', 'GB', 'CA', 'DE', 'FR')
GROUP BY country_code
ORDER BY sessions DESC;

\echo ''
\echo '===================================================='
\echo 'Query execution complete!'
\echo '===================================================='
\echo ''
\echo 'All 12 queries test:'
\echo '  - Bloom filters: session_id, user_id, product_id'
\echo '  - MinMax columns: event_date, event_type, device_type, country_code'
\echo '  - Z-order clustering: event_hour + session_id'
\echo '  - Sparse filtering: product fields (60% NULL), user fields (70% NULL)'
\echo ''
\echo 'Next: Phase 8 - Collect metrics'
\echo 'Run: psql -f sql/08_collect_metrics.sql'
\echo ''
