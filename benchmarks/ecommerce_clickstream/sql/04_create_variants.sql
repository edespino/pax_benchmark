--
-- Phase 4: Create Storage Variants
-- Creates 4 variants: AO, AOCO, PAX (no-cluster), PAX (clustered)
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 4: Create Storage Variants'
\echo '===================================================='
\echo ''

-- =====================================================
-- Variant 1: AO (Append-Only Row-Oriented) - Baseline
-- =====================================================

\echo 'Creating Variant 1: AO (row-oriented baseline)...'

DROP TABLE IF EXISTS ecommerce.clickstream_ao CASCADE;

CREATE TABLE ecommerce.clickstream_ao (
    -- Time dimension
    event_timestamp TIMESTAMP NOT NULL,
    event_date DATE NOT NULL,
    event_hour TIMESTAMP NOT NULL,

    -- Session/user identifiers
    session_id VARCHAR(64) NOT NULL,
    user_id VARCHAR(64),
    anonymous_id VARCHAR(64),

    -- Event classification
    event_type VARCHAR(50) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    page_url VARCHAR(500),
    page_category VARCHAR(100),

    -- Product context (nullable for non-product events)
    product_id VARCHAR(64),
    product_name VARCHAR(200),
    product_category VARCHAR(100),
    product_price NUMERIC(10,2),
    product_quantity INTEGER,

    -- Shopping cart state
    cart_value NUMERIC(12,2),
    cart_item_count INTEGER,

    -- User characteristics
    user_segment VARCHAR(50),
    is_returning_customer BOOLEAN,
    lifetime_value_bucket VARCHAR(20),

    -- Device/browser
    device_type VARCHAR(20),
    browser VARCHAR(50),
    os VARCHAR(50),
    screen_resolution VARCHAR(20),

    -- Marketing attribution
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    referrer_url VARCHAR(500),

    -- Geography
    country_code VARCHAR(2),
    region VARCHAR(100),
    city VARCHAR(100),

    -- Experiment/personalization
    experiment_id VARCHAR(64),
    variant_id VARCHAR(64),
    personalization_segment VARCHAR(100),

    -- Event metadata
    event_value NUMERIC(12,2),
    sequence_in_session INTEGER,
    time_on_page_seconds INTEGER
) WITH (
    appendonly=true,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (session_id);

\echo '  ✓ AO variant created'

-- =====================================================
-- Variant 2: AOCO (Append-Only Column-Oriented) - Current Best Practice
-- =====================================================

\echo 'Creating Variant 2: AOCO (column-oriented baseline)...'

DROP TABLE IF EXISTS ecommerce.clickstream_aoco CASCADE;

CREATE TABLE ecommerce.clickstream_aoco (
    -- Time dimension
    event_timestamp TIMESTAMP NOT NULL,
    event_date DATE NOT NULL,
    event_hour TIMESTAMP NOT NULL,

    -- Session/user identifiers
    session_id VARCHAR(64) NOT NULL,
    user_id VARCHAR(64),
    anonymous_id VARCHAR(64),

    -- Event classification
    event_type VARCHAR(50) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    page_url VARCHAR(500),
    page_category VARCHAR(100),

    -- Product context
    product_id VARCHAR(64),
    product_name VARCHAR(200),
    product_category VARCHAR(100),
    product_price NUMERIC(10,2),
    product_quantity INTEGER,

    -- Shopping cart state
    cart_value NUMERIC(12,2),
    cart_item_count INTEGER,

    -- User characteristics
    user_segment VARCHAR(50),
    is_returning_customer BOOLEAN,
    lifetime_value_bucket VARCHAR(20),

    -- Device/browser
    device_type VARCHAR(20),
    browser VARCHAR(50),
    os VARCHAR(50),
    screen_resolution VARCHAR(20),

    -- Marketing attribution
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    referrer_url VARCHAR(500),

    -- Geography
    country_code VARCHAR(2),
    region VARCHAR(100),
    city VARCHAR(100),

    -- Experiment/personalization
    experiment_id VARCHAR(64),
    variant_id VARCHAR(64),
    personalization_segment VARCHAR(100),

    -- Event metadata
    event_value NUMERIC(12,2),
    sequence_in_session INTEGER,
    time_on_page_seconds INTEGER
) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (session_id);

\echo '  ✓ AOCO variant created'

-- =====================================================
-- Variant 3: PAX (no-cluster) - Control Group
-- =====================================================

\echo 'Creating Variant 3: PAX (no-cluster control)...'

DROP TABLE IF EXISTS ecommerce.clickstream_pax_nocluster CASCADE;

CREATE TABLE ecommerce.clickstream_pax_nocluster (
    -- Time dimension
    event_timestamp TIMESTAMP NOT NULL,
    event_date DATE NOT NULL,
    event_hour TIMESTAMP NOT NULL,

    -- Session/user identifiers
    session_id VARCHAR(64) NOT NULL,
    user_id VARCHAR(64),
    anonymous_id VARCHAR(64),

    -- Event classification
    event_type VARCHAR(50) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    page_url VARCHAR(500),
    page_category VARCHAR(100),

    -- Product context
    product_id VARCHAR(64),
    product_name VARCHAR(200),
    product_category VARCHAR(100),
    product_price NUMERIC(10,2),
    product_quantity INTEGER,

    -- Shopping cart state
    cart_value NUMERIC(12,2),
    cart_item_count INTEGER,

    -- User characteristics
    user_segment VARCHAR(50),
    is_returning_customer BOOLEAN,
    lifetime_value_bucket VARCHAR(20),

    -- Device/browser
    device_type VARCHAR(20),
    browser VARCHAR(50),
    os VARCHAR(50),
    screen_resolution VARCHAR(20),

    -- Marketing attribution
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    referrer_url VARCHAR(500),

    -- Geography
    country_code VARCHAR(2),
    region VARCHAR(100),
    city VARCHAR(100),

    -- Experiment/personalization
    experiment_id VARCHAR(64),
    variant_id VARCHAR(64),
    personalization_segment VARCHAR(100),

    -- Event metadata
    event_value NUMERIC(12,2),
    sequence_in_session INTEGER,
    time_on_page_seconds INTEGER
) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Low overhead, use for ALL filterable columns (8 columns)
    minmax_columns='event_date,event_timestamp,event_type,product_category,device_type,country_code,cart_value,is_returning_customer',

    -- Bloom: ONLY high-cardinality columns (3 columns validated >10K)
    -- session_id (~200K), user_id (~15K), product_id (~40K)
    bloomfilter_columns='session_id,user_id,product_id',

    -- NO clustering (control group to isolate clustering effects)
    storage_format='porc'
) DISTRIBUTED BY (session_id);

\echo '  ✓ PAX no-cluster variant created (3 bloom filters, 8 minmax)'

-- =====================================================
-- Variant 4: PAX (clustered) - Optimized
-- =====================================================

\echo 'Creating Variant 4: PAX (clustered with Z-order)...'

DROP TABLE IF EXISTS ecommerce.clickstream_pax CASCADE;

CREATE TABLE ecommerce.clickstream_pax (
    -- Time dimension
    event_timestamp TIMESTAMP NOT NULL,
    event_date DATE NOT NULL,
    event_hour TIMESTAMP NOT NULL,

    -- Session/user identifiers
    session_id VARCHAR(64) NOT NULL,
    user_id VARCHAR(64),
    anonymous_id VARCHAR(64),

    -- Event classification
    event_type VARCHAR(50) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    page_url VARCHAR(500),
    page_category VARCHAR(100),

    -- Product context
    product_id VARCHAR(64),
    product_name VARCHAR(200),
    product_category VARCHAR(100),
    product_price NUMERIC(10,2),
    product_quantity INTEGER,

    -- Shopping cart state
    cart_value NUMERIC(12,2),
    cart_item_count INTEGER,

    -- User characteristics
    user_segment VARCHAR(50),
    is_returning_customer BOOLEAN,
    lifetime_value_bucket VARCHAR(20),

    -- Device/browser
    device_type VARCHAR(20),
    browser VARCHAR(50),
    os VARCHAR(50),
    screen_resolution VARCHAR(20),

    -- Marketing attribution
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    referrer_url VARCHAR(500),

    -- Geography
    country_code VARCHAR(2),
    region VARCHAR(100),
    city VARCHAR(100),

    -- Experiment/personalization
    experiment_id VARCHAR(64),
    variant_id VARCHAR(64),
    personalization_segment VARCHAR(100),

    -- Event metadata
    event_value NUMERIC(12,2),
    sequence_in_session INTEGER,
    time_on_page_seconds INTEGER
) USING pax WITH (
    compresstype='zstd',
    compresslevel=5,

    -- MinMax: Low overhead, use for ALL filterable columns (8 columns)
    minmax_columns='event_date,event_timestamp,event_type,product_category,device_type,country_code,cart_value,is_returning_customer',

    -- Bloom: ONLY high-cardinality columns (3 columns validated >10K)
    bloomfilter_columns='session_id,user_id,product_id',

    -- Z-order clustering: Time + session (funnel analysis pattern)
    cluster_type='zorder',
    cluster_columns='event_date,session_id',

    storage_format='porc'
) DISTRIBUTED BY (session_id);

\echo '  ✓ PAX clustered variant created (Z-order on event_hour + session_id)'

-- =====================================================
-- Summary
-- =====================================================

\echo ''
\echo '===================================================='
\echo 'All variants created!'
\echo '===================================================='
\echo ''

SELECT
    tablename AS variant,
    CASE
        WHEN tablename = 'clickstream_ao' THEN 'AO (row-oriented baseline)'
        WHEN tablename = 'clickstream_aoco' THEN 'AOCO (column-oriented baseline)'
        WHEN tablename = 'clickstream_pax_nocluster' THEN 'PAX (no-cluster control)'
        WHEN tablename = 'clickstream_pax' THEN 'PAX (clustered with Z-order)'
    END AS description,
    pg_size_pretty(pg_total_relation_size('ecommerce.' || tablename)) AS current_size
FROM pg_tables
WHERE schemaname = 'ecommerce'
  AND tablename LIKE 'clickstream_%'
ORDER BY tablename;

\echo ''
\echo 'Configuration summary:'
\echo '  - Bloom filters: session_id, user_id, product_id (3 high-cardinality columns)'
\echo '  - MinMax columns: 8 filterable columns'
\echo '  - Z-order clustering: event_hour + session_id (funnel analysis)'
\echo '  - Compression: ZSTD level 5 (all variants)'
\echo ''
\echo 'Next: Phase 5 - Generate 10M clickstream events'
\echo 'Run: psql -f sql/05_generate_data.sql'
\echo ''
