--
-- Phase 3: Data Generation - 10M ROW TEST
-- Medium-scale test to evaluate PAX features
--

\echo '================================================'
\echo 'PAX Benchmark - Phase 3: Data Generation (10M)'
\echo '================================================'
\echo ''
\echo 'Generating 10M rows for testing...'
\echo ''

\timing on

-- Set optimal parameters for bulk loading
SET statement_timeout = 0;
SET work_mem = '256MB';

\echo 'Generating 10M rows in PAX table...'

INSERT INTO benchmark.sales_fact_pax
SELECT
    -- Time dimensions (with date correlation to region for Z-order benefit)
    ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE AS sale_date,
    ('2020-01-01 00:00:00'::TIMESTAMP +
     (random() * 1460 * 86400)::INT * INTERVAL '1 second') AS sale_timestamp,

    -- Sequential IDs (good for delta encoding)
    gs AS order_id,
    (random() * 10000000)::INTEGER AS customer_id,
    (random() * 100000)::INTEGER AS product_id,

    -- Numeric measures
    (random() * 100 + 1)::INTEGER AS quantity,
    (random() * 1000 + 10)::NUMERIC(12,2) AS unit_price,
    CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END AS discount_pct,
    (random() * 50)::NUMERIC(12,2) AS tax_amount,
    (random() * 20)::NUMERIC(10,2) AS shipping_cost,
    (random() * 10000 + 100)::NUMERIC(14,2) AS total_amount,

    -- Categorical columns (skewed distribution, good for RLE + bloom filters)
    CASE (random() * 5)::INTEGER
        WHEN 0 THEN 'North America'
        WHEN 1 THEN 'Europe'
        WHEN 2 THEN 'Asia Pacific'
        WHEN 3 THEN 'Latin America'
        ELSE 'Middle East'
    END AS region,

    CASE (random() * 20)::INTEGER
        WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK'
        WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China'
        WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil'
        WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain'
        WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore'
        WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia'
        WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE'
        ELSE 'Other'
    END AS country,

    CASE (random() * 3)::INTEGER
        WHEN 0 THEN 'Online'
        WHEN 1 THEN 'Store'
        ELSE 'Phone'
    END AS sales_channel,

    CASE (random() * 4)::INTEGER
        WHEN 0 THEN 'Pending'
        WHEN 1 THEN 'Shipped'
        WHEN 2 THEN 'Delivered'
        ELSE 'Cancelled'
    END AS order_status,

    CASE (random() * 5)::INTEGER
        WHEN 0 THEN 'Credit Card'
        WHEN 1 THEN 'Debit Card'
        WHEN 2 THEN 'PayPal'
        WHEN 3 THEN 'Bank Transfer'
        ELSE 'Cash'
    END AS payment_method,

    -- Text fields
    'Category_' || (random() * 50)::TEXT AS product_category,
    'Segment_' || (random() * 10)::TEXT AS customer_segment,
    CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END AS promo_code,

    -- Low cardinality (great for RLE)
    CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END AS priority,
    (random() < 0.05) AS is_return,

    -- Sparse fields (mostly null)
    CASE WHEN random() < 0.05
        THEN CASE (random() * 3)::INTEGER
            WHEN 0 THEN 'Defective product'
            WHEN 1 THEN 'Wrong item shipped'
            ELSE 'Customer changed mind'
        END
        ELSE NULL
    END AS return_reason,

    CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END AS special_notes,

    -- Hash for bloom filter testing
    md5(gs::TEXT) AS transaction_hash

FROM generate_series(1, 10000000) gs;

\echo ''
\echo 'PAX table loaded! Now copying to other variants...'
\echo ''

-- Copy to AO variant
\echo 'Copying to AO table...'
INSERT INTO benchmark.sales_fact_ao SELECT * FROM benchmark.sales_fact_pax;

-- Copy to AOCO variant
\echo 'Copying to AOCO table...'
INSERT INTO benchmark.sales_fact_aoco SELECT * FROM benchmark.sales_fact_pax;

-- Copy to PAX no-cluster variant
\echo 'Copying to PAX no-cluster table...'
INSERT INTO benchmark.sales_fact_pax_nocluster SELECT * FROM benchmark.sales_fact_pax;

\echo ''
\echo 'Data generation complete!'
\echo ''

-- Analyze all tables
\echo 'Analyzing tables...'
ANALYZE benchmark.sales_fact_pax;
ANALYZE benchmark.sales_fact_ao;
ANALYZE benchmark.sales_fact_aoco;
ANALYZE benchmark.sales_fact_pax_nocluster;

-- Summary
\echo ''
\echo 'Final table sizes:'
SELECT tablename,
       pg_size_pretty(pg_total_relation_size('benchmark.'||tablename)) AS size,
       (SELECT COUNT(*) FROM benchmark.sales_fact_pax) AS row_count
FROM pg_tables
WHERE schemaname = 'benchmark'
  AND tablename LIKE 'sales_fact_%'
ORDER BY pg_total_relation_size('benchmark.'||tablename) DESC;

\timing off

\echo ''
\echo 'Next: Phase 4 - Optimize PAX table (clustering)'
