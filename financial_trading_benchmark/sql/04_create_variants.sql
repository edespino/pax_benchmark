--
-- Phase 4: Create Storage Variants
-- Creates 4 table variants: AO, AOCO, PAX (clustered), PAX (no-cluster)
-- Based on validated configuration from Phase 3
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 4: Create Storage Variants'
\echo '===================================================='
\echo ''

-- =====================================================
-- Base Table Structure (for reference)
-- =====================================================

\echo 'Creating 4 storage variants for comparison...'
\echo ''

-- =====================================================
-- Variant 1: AO (Append-Only Row-Oriented)
-- Baseline for comparison
-- =====================================================

\echo 'Variant 1: AO (Append-Only Row-Oriented)...'

CREATE TABLE trading.tick_data_ao (
    -- Time dimension
    trade_timestamp TIMESTAMP NOT NULL,
    trade_date DATE NOT NULL,
    trade_time_bucket TIMESTAMP NOT NULL,

    -- Identifiers
    trade_id BIGINT NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    exchange_id VARCHAR(10) NOT NULL,

    -- Price/volume
    price NUMERIC(18,6) NOT NULL,
    quantity INTEGER NOT NULL,
    volume_usd NUMERIC(20,2) NOT NULL,

    -- Market data
    bid_price NUMERIC(18,6),
    ask_price NUMERIC(18,6),
    bid_size INTEGER,
    ask_size INTEGER,

    -- Trade characteristics
    trade_type VARCHAR(10),
    buyer_type VARCHAR(20),
    seller_type VARCHAR(20),

    -- Conditions
    trade_condition VARCHAR(4),
    sale_condition VARCHAR(10),

    -- Derived fields
    price_change_bps NUMERIC(10,4),
    is_block_trade BOOLEAN,

    -- Audit
    sequence_number BIGINT,
    checksum VARCHAR(64)
) WITH (
    appendonly=true,
    orientation=row,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (symbol);

\echo '  ✓ tick_data_ao created (AO baseline)'
\echo ''

-- =====================================================
-- Variant 2: AOCO (Append-Only Column-Oriented)
-- Current best practice in Cloudberry
-- =====================================================

\echo 'Variant 2: AOCO (Append-Only Column-Oriented)...'

CREATE TABLE trading.tick_data_aoco (
    trade_timestamp TIMESTAMP NOT NULL,
    trade_date DATE NOT NULL,
    trade_time_bucket TIMESTAMP NOT NULL,
    trade_id BIGINT NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    exchange_id VARCHAR(10) NOT NULL,
    price NUMERIC(18,6) NOT NULL,
    quantity INTEGER NOT NULL,
    volume_usd NUMERIC(20,2) NOT NULL,
    bid_price NUMERIC(18,6),
    ask_price NUMERIC(18,6),
    bid_size INTEGER,
    ask_size INTEGER,
    trade_type VARCHAR(10),
    buyer_type VARCHAR(20),
    seller_type VARCHAR(20),
    trade_condition VARCHAR(4),
    sale_condition VARCHAR(10),
    price_change_bps NUMERIC(10,4),
    is_block_trade BOOLEAN,
    sequence_number BIGINT,
    checksum VARCHAR(64)
) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
) DISTRIBUTED BY (symbol);

\echo '  ✓ tick_data_aoco created (AOCO best practice)'
\echo ''

-- =====================================================
-- Variant 3: PAX (With Z-order Clustering)
-- VALIDATED configuration from Phase 3
-- =====================================================

\echo 'Variant 3: PAX (With Z-order Clustering)...'
\echo '  Using validated configuration from Phase 3:'
\echo '    - bloomfilter_columns: trade_id, symbol (ONLY high-cardinality)'
\echo '    - minmax_columns: All filterable columns'
\echo '    - cluster_columns: trade_time_bucket, symbol'

CREATE TABLE trading.tick_data_pax (
    trade_timestamp TIMESTAMP NOT NULL,
    trade_date DATE NOT NULL,
    trade_time_bucket TIMESTAMP NOT NULL,
    trade_id BIGINT NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    exchange_id VARCHAR(10) NOT NULL,
    price NUMERIC(18,6) NOT NULL,
    quantity INTEGER NOT NULL,
    volume_usd NUMERIC(20,2) NOT NULL,
    bid_price NUMERIC(18,6),
    ask_price NUMERIC(18,6),
    bid_size INTEGER,
    ask_size INTEGER,
    trade_type VARCHAR(10),
    buyer_type VARCHAR(20),
    seller_type VARCHAR(20),
    trade_condition VARCHAR(4),
    sale_condition VARCHAR(10),
    price_change_bps NUMERIC(10,4),
    is_block_trade BOOLEAN,
    sequence_number BIGINT,
    checksum VARCHAR(64)
) USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- MinMax statistics (low overhead, all filterable columns)
    minmax_columns='trade_date,trade_time_bucket,symbol,exchange_id,price,volume_usd,quantity,trade_type,bid_price,ask_price',

    -- Bloom filters: VALIDATED - only high-cardinality columns
    -- Based on Phase 2 analysis:
    --   trade_id: ~1M unique ✅ SAFE
    --   symbol: ~5,000 unique ✅ SAFE
    --   exchange_id: ~20 unique ❌ EXCLUDED (too low)
    --   trade_type: ~10 unique ❌ EXCLUDED (too low)
    bloomfilter_columns='trade_id,symbol',

    -- Z-order clustering for time-series + symbol queries
    -- Using trade_time_bucket (TIMESTAMP rounded to second) + symbol
    cluster_type='zorder',
    cluster_columns='trade_time_bucket,symbol',

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (symbol);

\echo '  ✓ tick_data_pax created (will be clustered in Phase 7)'
\echo ''

-- =====================================================
-- Variant 4: PAX No-Clustering (Control Group)
-- Same as PAX but WITHOUT Z-order clustering
-- =====================================================

\echo 'Variant 4: PAX No-Clustering (Control)...'

CREATE TABLE trading.tick_data_pax_nocluster (
    trade_timestamp TIMESTAMP NOT NULL,
    trade_date DATE NOT NULL,
    trade_time_bucket TIMESTAMP NOT NULL,
    trade_id BIGINT NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    exchange_id VARCHAR(10) NOT NULL,
    price NUMERIC(18,6) NOT NULL,
    quantity INTEGER NOT NULL,
    volume_usd NUMERIC(20,2) NOT NULL,
    bid_price NUMERIC(18,6),
    ask_price NUMERIC(18,6),
    bid_size INTEGER,
    ask_size INTEGER,
    trade_type VARCHAR(10),
    buyer_type VARCHAR(20),
    seller_type VARCHAR(20),
    trade_condition VARCHAR(4),
    sale_condition VARCHAR(10),
    price_change_bps NUMERIC(10,4),
    is_block_trade BOOLEAN,
    sequence_number BIGINT,
    checksum VARCHAR(64)
) USING pax WITH (
    -- Core compression
    compresstype='zstd',
    compresslevel=5,

    -- Same statistics as clustered PAX
    minmax_columns='trade_date,trade_time_bucket,symbol,exchange_id,price,volume_usd,quantity,trade_type,bid_price,ask_price',
    bloomfilter_columns='trade_id,symbol',

    -- NO clustering (this is the key difference)
    -- cluster_type and cluster_columns intentionally omitted

    -- Storage format
    storage_format='porc'
) DISTRIBUTED BY (symbol);

\echo '  ✓ tick_data_pax_nocluster created (no clustering)'
\echo ''

-- =====================================================
-- Verify Table Creation
-- =====================================================

\echo 'Verification - All 4 variants created:'
\echo ''

SELECT
    tablename,
    CASE
        WHEN tablename = 'tick_data_ao' THEN 'AO (row-oriented baseline)'
        WHEN tablename = 'tick_data_aoco' THEN 'AOCO (column-oriented best practice)'
        WHEN tablename = 'tick_data_pax' THEN 'PAX (with Z-order clustering)'
        WHEN tablename = 'tick_data_pax_nocluster' THEN 'PAX (no clustering - control)'
    END AS description,
    pg_size_pretty(pg_total_relation_size('trading.' || tablename)) AS current_size
FROM pg_tables
WHERE schemaname = 'trading'
  AND tablename LIKE 'tick_data_%'
ORDER BY tablename;

\echo ''
\echo '===================================================='
\echo 'All 4 storage variants created successfully!'
\echo '===================================================='
\echo ''
\echo 'Configuration highlights:'
\echo '  ✅ Bloom filters ONLY on trade_id and symbol (high cardinality)'
\echo '  ❌ Excluded exchange_id and trade_type (low cardinality)'
\echo '  ✅ Z-order on time + symbol (most common query pattern)'
\echo ''
\echo 'Next: Phase 5 - Generate 10M trades'
