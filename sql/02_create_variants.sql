--
-- Phase 2: Create Storage Variants (AO, AOCO, PAX)
-- Creates three versions of the fact table for comparison
--

\echo '================================================='
\echo 'PAX Benchmark - Phase 2: Create Storage Variants'
\echo '================================================='
\echo ''

-- =============================================
-- Base Fact Table Definition
-- =============================================

\echo 'Defining base fact table structure...'

-- First create a template table (will be dropped)
CREATE TEMP TABLE sales_fact_template (
    -- Time dimensions (good for Z-order clustering)
    sale_date DATE NOT NULL,
    sale_timestamp TIMESTAMP NOT NULL,

    -- Numeric IDs (good for min/max stats + delta encoding)
    order_id BIGINT NOT NULL,
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,

    -- Numeric measures
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    discount_pct NUMERIC(5,2),
    tax_amount NUMERIC(12,2),
    shipping_cost NUMERIC(10,2),
    total_amount NUMERIC(14,2) NOT NULL,

    -- Categorical columns (good for bloom filters + RLE compression)
    region VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL,
    sales_channel VARCHAR(20) NOT NULL,  -- 'Online', 'Store', 'Phone'
    order_status VARCHAR(20) NOT NULL,   -- 'Pending', 'Shipped', 'Delivered', 'Cancelled'
    payment_method VARCHAR(30),

    -- Text fields (varying compression efficiency)
    product_category VARCHAR(100),
    customer_segment VARCHAR(50),
    promo_code VARCHAR(50),

    -- Low cardinality (great for RLE)
    priority CHAR(1),  -- 'L', 'M', 'H'
    is_return BOOLEAN,

    -- Sparse columns (many nulls)
    return_reason TEXT,
    special_notes TEXT,

    -- Hash value (bloom filter test)
    transaction_hash VARCHAR(64)
);

\echo 'Base structure defined'
\echo ''

-- =============================================
-- Variant 1: AO (Append-Only Row-Oriented)
-- Baseline for comparison
-- =============================================

\echo 'Creating Variant 1: AO (Append-Only Row-Oriented)...'

CREATE TABLE benchmark.sales_fact_ao (LIKE sales_fact_template)
WITH (
    appendonly=true,
    orientation=row,
    compresstype=zstd,
    compresslevel=5
)
DISTRIBUTED BY (order_id);

\echo '  ✓ sales_fact_ao created (AO baseline)'
\echo ''

-- =============================================
-- Variant 2: AOCO (Append-Only Column-Oriented)
-- Current best practice in Cloudberry
-- =============================================

\echo 'Creating Variant 2: AOCO (Append-Only Column-Oriented)...'

CREATE TABLE benchmark.sales_fact_aoco (LIKE sales_fact_template)
WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
)
DISTRIBUTED BY (order_id);

\echo '  ✓ sales_fact_aoco created (AOCO best practice)'
\echo ''

-- =============================================
-- Variant 3: PAX (Optimized with all features)
-- Showcase configuration with:
-- - Per-column compression
-- - Statistics (min/max + bloom filters)
-- - Z-order clustering
-- =============================================

\echo 'Creating Variant 3: PAX (Optimized)...'

CREATE TABLE benchmark.sales_fact_pax (LIKE sales_fact_template)
USING pax WITH (
    -- Primary compression strategy
    compresstype='zstd',
    compresslevel=5,

    -- Statistics for sparse filtering
    -- min/max: good for range queries on ordered/semi-ordered data
    minmax_columns='sale_date,order_id,customer_id,product_id,total_amount,quantity',

    -- bloom filters: good for equality/IN queries on high-cardinality columns
    bloomfilter_columns='region,country,sales_channel,order_status,product_category,transaction_hash',

    -- Z-order clustering for correlated dimensions
    -- sale_date + region are often queried together
    cluster_type='zorder',
    cluster_columns='sale_date,region',

    -- Storage format (porc for Cloudberry executor)
    storage_format='porc'
)
DISTRIBUTED BY (order_id);

\echo '  ✓ sales_fact_pax created (base table)'
\echo ''

-- =============================================
-- PAX Per-Column Encoding Optimization
-- Apply specialized encodings for different column types
-- =============================================

\echo 'Applying per-column encoding to PAX table...'

-- Delta encoding for sequential/monotonic columns
ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN sale_date SET ENCODING (compresstype=delta);

ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN order_id SET ENCODING (compresstype=delta);

ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN quantity SET ENCODING (compresstype=delta);

\echo '  ✓ Delta encoding applied to date/ID columns'

-- RLE encoding for low-cardinality columns
ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN priority SET ENCODING (compresstype=RLE_TYPE);

ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN is_return SET ENCODING (compresstype=RLE_TYPE);

ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN order_status SET ENCODING (compresstype=RLE_TYPE);

ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN sales_channel SET ENCODING (compresstype=RLE_TYPE);

\echo '  ✓ RLE encoding applied to categorical columns'

-- High compression for text fields
ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN product_category SET ENCODING (compresstype=zstd, compresslevel=9);

ALTER TABLE benchmark.sales_fact_pax
    ALTER COLUMN customer_segment SET ENCODING (compresstype=zstd, compresslevel=9);

\echo '  ✓ High-level ZSTD applied to text columns'
\echo ''

-- =============================================
-- Verify table creation
-- =============================================

\echo 'Verifying table creation...'
\echo ''

SELECT tablename,
       CASE
           WHEN tablename LIKE '%_ao' THEN 'AO (baseline)'
           WHEN tablename LIKE '%_aoco' THEN 'AOCO (best practice)'
           WHEN tablename LIKE '%_pax' THEN 'PAX (optimized)'
       END AS variant,
       pg_size_pretty(pg_total_relation_size('benchmark.'||tablename)) AS current_size
FROM pg_tables
WHERE schemaname = 'benchmark'
  AND tablename LIKE 'sales_fact_%'
ORDER BY tablename;

\echo ''
\echo '================================================='
\echo 'Storage variants created successfully!'
\echo '================================================='
\echo ''
\echo 'Next: Phase 3 - Generate data (200M rows)'
