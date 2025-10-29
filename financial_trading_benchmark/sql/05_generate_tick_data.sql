--
-- Phase 5: Generate Trading Tick Data
-- Generates 10M high-frequency trades with realistic patterns
-- Populates all 4 storage variants (AO, AOCO, PAX, PAX no-cluster)
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 5: Generate Tick Data'
\echo '===================================================='
\echo ''
\echo 'Generating 10M trades (this will take 3-4 minutes)...'
\echo ''

-- =====================================================
-- Generate Data into AO (Primary Variant)
-- =====================================================

\echo 'Step 1/4: Populating AO variant (10M rows)...'

INSERT INTO trading.tick_data_ao
WITH
-- Preload symbol data for faster joins
symbol_cache AS (
    SELECT
        symbol,
        exchange_id,
        price_range_min,
        price_range_max,
        ROW_NUMBER() OVER (ORDER BY symbol) - 1 AS symbol_idx
    FROM trading.symbols
    WHERE is_active = true
    LIMIT 5000
),
symbol_count AS (
    SELECT COUNT(*) AS total FROM symbol_cache
),
-- Generate trades with realistic intraday patterns
trade_generation AS (
    SELECT
        -- Time dimension (market hours: 9:30 - 16:00 = 6.5 hours = 23,400 seconds)
        -- Microsecond precision for HFT data
        timestamp '2025-10-29 09:30:00' +
            ((gs / 10000000.0) * interval '6 hours 30 minutes') +
            (random() * interval '1 second') AS trade_timestamp,

        DATE '2025-10-29' AS trade_date,

        -- Time bucket (rounded to second for Z-order)
        date_trunc('second',
            timestamp '2025-10-29 09:30:00' +
            ((gs / 10000000.0) * interval '6 hours 30 minutes') +
            (random() * interval '1 second')
        ) AS trade_time_bucket,

        -- Unique trade ID
        gs AS trade_id,

        -- Select symbol (Zipf distribution: 20% of symbols get 80% of trades)
        CASE
            WHEN random() < 0.80 THEN  -- 80% of trades
                (SELECT symbol FROM symbol_cache OFFSET (random() * 999)::INT LIMIT 1)
            ELSE  -- 20% of trades on long tail
                (SELECT symbol FROM symbol_cache OFFSET (1000 + random() * 3999)::INT LIMIT 1)
        END AS symbol,

        -- Symbol metadata
        s.exchange_id,
        s.price_range_min,
        s.price_range_max,

        -- Random for price calculation
        random() AS price_rand,
        random() AS volume_rand

    FROM generate_series(1, 10000000) gs,
         symbol_count sc
    CROSS JOIN LATERAL (
        SELECT *
        FROM symbol_cache
        OFFSET (
            CASE
                WHEN random() < 0.80 THEN (random() * 999)::INT  -- Hot stocks
                ELSE 1000 + (random() * 3999)::INT               -- Long tail
            END
        )
        LIMIT 1
    ) s
)
SELECT
    trade_timestamp,
    trade_date,
    trade_time_bucket,
    trade_id,
    symbol,
    exchange_id,

    -- Price (within symbol's range, with intraday volatility)
    (price_range_min + price_rand * (price_range_max - price_range_min))::NUMERIC(18,6) AS price,

    -- Quantity (log-normal distribution: many small trades, few large trades)
    CASE
        WHEN volume_rand < 0.70 THEN (100 + (random() * 900)::INT)        -- 70%: 100-1,000 shares
        WHEN volume_rand < 0.90 THEN (1000 + (random() * 9000)::INT)      -- 20%: 1K-10K shares
        WHEN volume_rand < 0.98 THEN (10000 + (random() * 90000)::INT)    -- 8%: 10K-100K shares
        ELSE (100000 + (random() * 900000)::INT)                          -- 2%: 100K-1M shares (block trades)
    END AS quantity,

    -- Volume in USD
    ((price_range_min + price_rand * (price_range_max - price_range_min)) *
     CASE
        WHEN volume_rand < 0.70 THEN (100 + (random() * 900)::INT)
        WHEN volume_rand < 0.90 THEN (1000 + (random() * 9000)::INT)
        WHEN volume_rand < 0.98 THEN (10000 + (random() * 90000)::INT)
        ELSE (100000 + (random() * 900000)::INT)
     END)::NUMERIC(20,2) AS volume_usd,

    -- Bid price (slightly below trade price)
    ((price_range_min + price_rand * (price_range_max - price_range_min)) * 0.9995)::NUMERIC(18,6) AS bid_price,

    -- Ask price (slightly above trade price)
    ((price_range_min + price_rand * (price_range_max - price_range_min)) * 1.0005)::NUMERIC(18,6) AS ask_price,

    -- Bid/ask sizes
    (100 + (random() * 5000)::INT) AS bid_size,
    (100 + (random() * 5000)::INT) AS ask_size,

    -- Trade type (realistic distribution)
    CASE
        WHEN random() < 0.65 THEN 'market'
        WHEN random() < 0.85 THEN 'limit'
        WHEN random() < 0.92 THEN 'stop'
        WHEN random() < 0.96 THEN 'stop_limit'
        WHEN random() < 0.98 THEN 'iceberg'
        ELSE (ARRAY['fill_or_kill','immediate_or_cancel','all_or_none','market_on_close','limit_on_close'])[1 + (random() * 4)::INT]
    END AS trade_type,

    -- Buyer/seller types
    CASE
        WHEN random() < 0.35 THEN 'institutional'
        WHEN random() < 0.70 THEN 'retail'
        WHEN random() < 0.85 THEN 'market_maker'
        WHEN random() < 0.95 THEN 'algorithmic'
        ELSE 'high_frequency'
    END AS buyer_type,

    CASE
        WHEN random() < 0.35 THEN 'institutional'
        WHEN random() < 0.70 THEN 'retail'
        WHEN random() < 0.85 THEN 'market_maker'
        WHEN random() < 0.95 THEN 'algorithmic'
        ELSE 'high_frequency'
    END AS seller_type,

    -- Trade condition (regulatory codes, sparse distribution)
    (ARRAY['@','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
           '1','2','3','4','5','6','7','8','9','A1','A2','B1','B2','C1','C2','D1','D2','E1','E2','F1','F2','G1','G2','H1','H2'])[1 + (random() * 49)::INT] AS trade_condition,

    -- Sale condition
    CASE
        WHEN random() < 0.80 THEN 'REGULAR'
        WHEN random() < 0.90 THEN 'CASH'
        WHEN random() < 0.95 THEN 'NEXT_DAY'
        ELSE (ARRAY['SELLER','SPECIAL_TERMS','WHEN_ISSUED','OPENING','CLOSING','CONTINGENT','AVERAGE_PRICE'])[1 + (random() * 6)::INT]
    END AS sale_condition,

    -- Price change in basis points (vs previous, simulated)
    ((random() - 0.5) * 50)::NUMERIC(10,4) AS price_change_bps,

    -- Block trade flag (quantity >= 10,000 shares)
    (CASE
        WHEN volume_rand >= 0.98 THEN true
        ELSE false
    END) AS is_block_trade,

    -- Audit fields
    trade_id AS sequence_number,
    md5(trade_id::TEXT || random()::TEXT) AS checksum

FROM trade_generation;

\echo '  ✓ AO variant populated'
\echo ''

-- =====================================================
-- Copy to Other Variants
-- =====================================================

\echo 'Step 2/4: Copying to AOCO variant...'
INSERT INTO trading.tick_data_aoco SELECT * FROM trading.tick_data_ao;
\echo '  ✓ AOCO variant populated'
\echo ''

\echo 'Step 3/4: Copying to PAX (clustered) variant...'
INSERT INTO trading.tick_data_pax SELECT * FROM trading.tick_data_ao;
\echo '  ✓ PAX (clustered) variant populated'
\echo ''

\echo 'Step 4/4: Copying to PAX (no-cluster) variant...'
INSERT INTO trading.tick_data_pax_nocluster SELECT * FROM trading.tick_data_ao;
\echo '  ✓ PAX (no-cluster) variant populated'
\echo ''

-- =====================================================
-- Analyze Tables
-- =====================================================

\echo 'Running ANALYZE on all variants...'

ANALYZE trading.tick_data_ao;
ANALYZE trading.tick_data_aoco;
ANALYZE trading.tick_data_pax;
ANALYZE trading.tick_data_pax_nocluster;

\echo '  ✓ Statistics collected for all variants'
\echo ''

-- =====================================================
-- Verification
-- =====================================================

\echo '===================================================='
\echo 'Data Generation Summary'
\echo '===================================================='
\echo ''

SELECT
    'tick_data_ao' AS variant,
    COUNT(*) AS row_count,
    COUNT(DISTINCT symbol) AS unique_symbols,
    COUNT(DISTINCT trade_date) AS trading_days,
    pg_size_pretty(pg_total_relation_size('trading.tick_data_ao')) AS size
FROM trading.tick_data_ao
UNION ALL
SELECT
    'tick_data_aoco',
    COUNT(*),
    COUNT(DISTINCT symbol),
    COUNT(DISTINCT trade_date),
    pg_size_pretty(pg_total_relation_size('trading.tick_data_aoco'))
FROM trading.tick_data_aoco
UNION ALL
SELECT
    'tick_data_pax',
    COUNT(*),
    COUNT(DISTINCT symbol),
    COUNT(DISTINCT trade_date),
    pg_size_pretty(pg_total_relation_size('trading.tick_data_pax'))
FROM trading.tick_data_pax
UNION ALL
SELECT
    'tick_data_pax_nocluster',
    COUNT(*),
    COUNT(DISTINCT symbol),
    COUNT(DISTINCT trade_date),
    pg_size_pretty(pg_total_relation_size('trading.tick_data_pax_nocluster'))
FROM trading.tick_data_pax_nocluster;

\echo ''
\echo '===================================================='
\echo 'Phase 5 complete!'
\echo '===================================================='
\echo ''
\echo '10M trades generated across all 4 variants'
\echo 'Next: Phase 6 - Validate configuration (post-creation bloat check)'
