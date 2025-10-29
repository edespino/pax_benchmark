--
-- Phase 3: Data Generation (200M rows, ~70GB)
-- Generates realistic data with patterns that benefit PAX features
--

\echo '================================================'
\echo 'PAX Benchmark - Phase 3: Data Generation'
\echo '================================================'
\echo ''
\echo 'WARNING: This will generate 200M rows (~70GB)'
\echo 'Estimated time: 30-60 minutes depending on cluster'
\echo ''

\timing on

-- Set optimal parameters for bulk loading
SET statement_timeout = 0;
SET work_mem = '256MB';

-- =============================================
-- Generate data in PAX table first (most optimized for inserts)
-- Then copy to AO and AOCO variants
-- =============================================

\echo 'Generating 200M rows in PAX table...'
\echo 'Progress markers every 20M rows:'
\echo ''

-- Batch 1: 20M rows
\echo '[1/10] Generating rows 1-20M...'
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

FROM generate_series(1, 20000000) gs;

-- Repeat for remaining batches
\echo '[2/10] Generating rows 20M-40M...'
INSERT INTO benchmark.sales_fact_pax
SELECT
    ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE,
    ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'),
    gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER,
    (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2),
    CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END,
    (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2),
    (random() * 10000 + 100)::NUMERIC(14,2),
    CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END,
    CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END,
    CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END,
    CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END,
    CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END,
    'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT,
    CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END,
    CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END,
    (random() < 0.05),
    CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END,
    CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END,
    md5(gs::TEXT)
FROM generate_series(20000001, 40000000) gs;

-- Continue for remaining 8 batches (showing compact version)
\echo '[3/10] Generating rows 40M-60M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(40000001, 60000000) gs;

\echo '[4/10] Generating rows 60M-80M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(60000001, 80000000) gs;

\echo '[5/10] Generating rows 80M-100M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(80000001, 100000000) gs;

\echo '[6/10] Generating rows 100M-120M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(100000001, 120000000) gs;

\echo '[7/10] Generating rows 120M-140M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(120000001, 140000000) gs;

\echo '[8/10] Generating rows 140M-160M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(140000001, 160000000) gs;

\echo '[9/10] Generating rows 160M-180M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(160000001, 180000000) gs;

\echo '[10/10] Generating rows 180M-200M...'
INSERT INTO benchmark.sales_fact_pax SELECT ('2020-01-01'::DATE + (random() * 1460)::INT)::DATE, ('2020-01-01 00:00:00'::TIMESTAMP + (random() * 1460 * 86400)::INT * INTERVAL '1 second'), gs, (random() * 10000000)::INTEGER, (random() * 100000)::INTEGER, (random() * 100 + 1)::INTEGER, (random() * 1000 + 10)::NUMERIC(12,2), CASE WHEN random() < 0.3 THEN (random() * 20)::NUMERIC(5,2) ELSE NULL END, (random() * 50)::NUMERIC(12,2), (random() * 20)::NUMERIC(10,2), (random() * 10000 + 100)::NUMERIC(14,2), CASE (random() * 5)::INTEGER WHEN 0 THEN 'North America' WHEN 1 THEN 'Europe' WHEN 2 THEN 'Asia Pacific' WHEN 3 THEN 'Latin America' ELSE 'Middle East' END, CASE (random() * 20)::INTEGER WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK' WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'China' WHEN 6 THEN 'Japan' WHEN 7 THEN 'India' WHEN 8 THEN 'Brazil' WHEN 9 THEN 'Mexico' WHEN 10 THEN 'Australia' WHEN 11 THEN 'Spain' WHEN 12 THEN 'Italy' WHEN 13 THEN 'Netherlands' WHEN 14 THEN 'Singapore' WHEN 15 THEN 'South Korea' WHEN 16 THEN 'Russia' WHEN 17 THEN 'Indonesia' WHEN 18 THEN 'Saudi Arabia' WHEN 19 THEN 'UAE' ELSE 'Other' END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'Online' WHEN 1 THEN 'Store' ELSE 'Phone' END, CASE (random() * 4)::INTEGER WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END, CASE (random() * 5)::INTEGER WHEN 0 THEN 'Credit Card' WHEN 1 THEN 'Debit Card' WHEN 2 THEN 'PayPal' WHEN 3 THEN 'Bank Transfer' ELSE 'Cash' END, 'Category_' || (random() * 50)::TEXT, 'Segment_' || (random() * 10)::TEXT, CASE WHEN random() < 0.2 THEN 'PROMO' || (random() * 100)::TEXT ELSE NULL END, CASE (random() * 3)::INTEGER WHEN 0 THEN 'L' WHEN 1 THEN 'M' ELSE 'H' END, (random() < 0.05), CASE WHEN random() < 0.05 THEN CASE (random() * 3)::INTEGER WHEN 0 THEN 'Defective product' WHEN 1 THEN 'Wrong item shipped' ELSE 'Customer changed mind' END ELSE NULL END, CASE WHEN random() < 0.1 THEN 'Special handling required' ELSE NULL END, md5(gs::TEXT) FROM generate_series(180000001, 200000000) gs;

\echo ''
\echo 'PAX table loaded! Now copying to AO and AOCO variants...'
\echo ''

-- Copy to AO variant
\echo 'Copying to AO table...'
INSERT INTO benchmark.sales_fact_ao SELECT * FROM benchmark.sales_fact_pax;

-- Copy to AOCO variant
\echo 'Copying to AOCO table...'
INSERT INTO benchmark.sales_fact_aoco SELECT * FROM benchmark.sales_fact_pax;

\echo ''
\echo 'Data generation complete!'
\echo ''

-- Summary
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
