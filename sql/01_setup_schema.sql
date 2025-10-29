--
-- Phase 1: Schema Setup for PAX Benchmark
-- Creates benchmark schema and dimension tables
--

\echo '========================================='
\echo 'PAX Benchmark - Phase 1: Schema Setup'
\echo '========================================='
\echo ''

-- Create benchmark schema
DROP SCHEMA IF EXISTS benchmark CASCADE;
CREATE SCHEMA benchmark;

\echo 'Created benchmark schema'
\echo ''

-- =============================================
-- Dimension Table: Customers (~5GB, 10M rows)
-- =============================================

\echo 'Creating customers dimension table...'

CREATE TABLE benchmark.customers (
    customer_id INTEGER PRIMARY KEY,
    customer_name VARCHAR(200),
    email VARCHAR(200),
    phone VARCHAR(50),
    registration_date DATE,
    lifetime_value NUMERIC(14,2),
    segment VARCHAR(50),
    region VARCHAR(50),
    country VARCHAR(50),
    is_premium BOOLEAN,
    credit_limit NUMERIC(12,2)
) DISTRIBUTED BY (customer_id);

\echo 'Generating customer data (10M rows)...'

INSERT INTO benchmark.customers
SELECT
    gs AS customer_id,
    'Customer_' || gs AS customer_name,
    'customer' || gs || '@email.com' AS email,
    '+1-' || LPAD((random() * 9999999999)::BIGINT::TEXT, 10, '0') AS phone,
    ('2015-01-01'::DATE + (random() * 3000)::INT)::DATE AS registration_date,
    (random() * 100000 + 100)::NUMERIC(14,2) AS lifetime_value,
    CASE (random() * 5)::INTEGER
        WHEN 0 THEN 'Enterprise'
        WHEN 1 THEN 'SMB'
        WHEN 2 THEN 'Individual'
        WHEN 3 THEN 'Government'
        ELSE 'Education'
    END AS segment,
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
        ELSE 'Other'
    END AS country,
    (random() < 0.2) AS is_premium,
    CASE WHEN random() < 0.2 THEN (random() * 100000 + 10000)::NUMERIC(12,2) ELSE NULL END AS credit_limit
FROM generate_series(1, 10000000) gs;

\echo 'Customer data generated'
\echo ''

-- =============================================
-- Dimension Table: Products (~2GB, 100K rows)
-- =============================================

\echo 'Creating products dimension table...'

CREATE TABLE benchmark.products (
    product_id INTEGER PRIMARY KEY,
    product_name VARCHAR(500),
    category VARCHAR(100),
    subcategory VARCHAR(100),
    brand VARCHAR(100),
    unit_cost NUMERIC(12,2),
    list_price NUMERIC(12,2),
    launch_date DATE,
    is_active BOOLEAN,
    weight_kg NUMERIC(8,2),
    dimensions VARCHAR(50)
) DISTRIBUTED BY (product_id);

\echo 'Generating product data (100K rows)...'

INSERT INTO benchmark.products
SELECT
    gs AS product_id,
    'Product_' || gs || '_' || md5(gs::TEXT) AS product_name,
    CASE (random() * 20)::INTEGER
        WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Computers' WHEN 2 THEN 'Home & Garden'
        WHEN 3 THEN 'Sports' WHEN 4 THEN 'Toys' WHEN 5 THEN 'Fashion'
        WHEN 6 THEN 'Books' WHEN 7 THEN 'Food' WHEN 8 THEN 'Automotive'
        WHEN 9 THEN 'Health' WHEN 10 THEN 'Beauty' WHEN 11 THEN 'Office'
        WHEN 12 THEN 'Pet Supplies' WHEN 13 THEN 'Industrial' WHEN 14 THEN 'Music'
        ELSE 'Other'
    END AS category,
    'Subcategory_' || (random() * 50)::TEXT AS subcategory,
    'Brand_' || (random() * 100)::TEXT AS brand,
    (random() * 500 + 10)::NUMERIC(12,2) AS unit_cost,
    (random() * 1000 + 20)::NUMERIC(12,2) AS list_price,
    ('2018-01-01'::DATE + (random() * 2000)::INT)::DATE AS launch_date,
    (random() < 0.85) AS is_active,
    (random() * 50 + 0.1)::NUMERIC(8,2) AS weight_kg,
    LPAD((random() * 100)::INT::TEXT, 2, '0') || 'x' ||
    LPAD((random() * 100)::INT::TEXT, 2, '0') || 'x' ||
    LPAD((random() * 100)::INT::TEXT, 2, '0') || 'cm' AS dimensions
FROM generate_series(1, 100000) gs;

\echo 'Product data generated'
\echo ''

-- =============================================
-- Analyze dimension tables
-- =============================================

\echo 'Analyzing dimension tables...'
ANALYZE benchmark.customers;
ANALYZE benchmark.products;

-- =============================================
-- Summary
-- =============================================

\echo ''
\echo 'Schema setup complete!'
\echo ''
\echo 'Dimension Tables Created:'
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'benchmark'
ORDER BY tablename;

\echo ''
\echo 'Ready for Phase 2: Create storage variants'
