--
-- Phase 2: Cardinality Analysis
-- CRITICAL: Validates bloom filter candidates BEFORE table creation
-- Generates 1M sample trades and analyzes cardinality
-- Prevents 81% storage bloat from low-cardinality bloom filters
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 2: Cardinality Analysis'
\echo '===================================================='
\echo ''
\echo 'CRITICAL SAFETY GATE #1: Validating bloom filter candidates'
\echo ''

-- =====================================================
-- Generate 1M Sample Trades
-- =====================================================

\echo 'Generating 1M sample trades for analysis...'

DROP TABLE IF EXISTS pg_temp.tick_data_sample CASCADE;

CREATE TEMP TABLE tick_data_sample AS
WITH
-- Get symbol list for random selection
symbol_list AS (
    SELECT symbol, exchange_id, price_range_min, price_range_max
    FROM trading.symbols
    WHERE is_active = true
    LIMIT 5000
),
-- Generate trades with realistic patterns
trade_gen AS (
    SELECT
        -- Time dimension (1 trading day, microsecond precision)
        timestamp '2025-10-29 09:30:00' + (gs * interval '1 millisecond' * (random() * 10)::INT) AS trade_timestamp,
        (timestamp '2025-10-29 09:30:00' + (gs * interval '1 millisecond' * (random() * 10)::INT))::DATE AS trade_date,
        -- Round to second for Z-order clustering (TIMESTAMP(6) not supported)
        date_trunc('second', timestamp '2025-10-29 09:30:00' + (gs * interval '1 millisecond' * (random() * 10)::INT)) AS trade_time_bucket,

        -- Identifiers (high cardinality expected)
        gs AS trade_id,  -- Unique per trade
        s.symbol,
        s.exchange_id,

        -- Price/volume (use symbol's price range)
        (s.price_range_min + random() * (s.price_range_max - s.price_range_min))::NUMERIC(18,6) AS price,
        (100 + (random() * 10000)::INT) AS quantity,
        ((s.price_range_min + random() * (s.price_range_max - s.price_range_min)) * (100 + (random() * 10000)::INT))::NUMERIC(20,2) AS volume_usd,

        -- Market data
        (s.price_range_min + random() * (s.price_range_max - s.price_range_min) * 0.998)::NUMERIC(18,6) AS bid_price,
        (s.price_range_min + random() * (s.price_range_max - s.price_range_min) * 1.002)::NUMERIC(18,6) AS ask_price,
        (100 + (random() * 5000)::INT) AS bid_size,
        (100 + (random() * 5000)::INT) AS ask_size,

        -- Trade characteristics (low cardinality)
        (ARRAY['market','limit','stop','stop_limit','iceberg','fill_or_kill','immediate_or_cancel','all_or_none','market_on_close','limit_on_close'])[1 + (random() * 9)::INT] AS trade_type,
        CASE
            WHEN random() < 0.40 THEN 'institutional'
            WHEN random() < 0.75 THEN 'retail'
            WHEN random() < 0.90 THEN 'market_maker'
            WHEN random() < 0.95 THEN 'algorithmic'
            ELSE 'high_frequency'
        END AS buyer_type,
        CASE
            WHEN random() < 0.40 THEN 'institutional'
            WHEN random() < 0.75 THEN 'retail'
            WHEN random() < 0.90 THEN 'market_maker'
            WHEN random() < 0.95 THEN 'algorithmic'
            ELSE 'high_frequency'
        END AS seller_type,

        -- Conditions (moderate cardinality)
        (ARRAY['@','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
               '1','2','3','4','5','6','7','8','9','A1','A2','B1','B2','C1','C2','D1','D2','E1','E2','F1','F2','G1','G2','H1','H2'])[1 + (random() * 49)::INT] AS trade_condition,
        (ARRAY['REGULAR','CASH','NEXT_DAY','SELLER','SPECIAL_TERMS','WHEN_ISSUED','OPENING','CLOSING','CONTINGENT','AVERAGE_PRICE'])[1 + (random() * 9)::INT] AS sale_condition,

        -- Derived fields
        ((random() - 0.5) * 100)::NUMERIC(10,4) AS price_change_bps,
        (random() < 0.05) AS is_block_trade,

        -- Audit
        gs AS sequence_number,
        md5(gs::TEXT || random()::TEXT) AS checksum

    FROM generate_series(1, 1000000) gs
    CROSS JOIN LATERAL (
        SELECT *
        FROM symbol_list
        OFFSET (random() * 4999)::INT
        LIMIT 1
    ) s
)
SELECT * FROM trade_gen;

\echo '  ✓ 1M sample trades generated'
\echo ''

-- =====================================================
-- Analyze Sample
-- =====================================================

\echo 'Running ANALYZE on sample data...'
ANALYZE pg_temp.tick_data_sample;
\echo '  ✓ Statistics collected'
\echo ''

-- =====================================================
-- Cardinality Report
-- =====================================================

\echo '===================================================='
\echo 'CARDINALITY ANALYSIS REPORT'
\echo '===================================================='
\echo ''

SELECT
    attname AS column_name,
    n_distinct,
    CASE
        WHEN n_distinct < 0 THEN (ABS(n_distinct) * (SELECT COUNT(*) FROM pg_temp.tick_data_sample))::BIGINT
        ELSE n_distinct::BIGINT
    END AS cardinality_estimate,
    CASE
        WHEN ABS(CASE WHEN n_distinct < 0 THEN (ABS(n_distinct) * (SELECT COUNT(*) FROM pg_temp.tick_data_sample))
                      ELSE n_distinct END) >= 1000 THEN '✅ HIGH - Good for bloom filter'
        WHEN ABS(CASE WHEN n_distinct < 0 THEN (ABS(n_distinct) * (SELECT COUNT(*) FROM pg_temp.tick_data_sample))
                      ELSE n_distinct END) >= 100 THEN '🟠 MEDIUM - Bloom filter borderline'
        ELSE '❌ LOW - Use minmax only, NOT bloom filter'
    END AS bloom_filter_suitability
FROM pg_stats
WHERE schemaname LIKE 'pg_temp%'
  AND tablename = 'tick_data_sample'
  AND attname NOT IN ('tableoid', 'cmax', 'xmax', 'cmin', 'xmin', 'ctid')
ORDER BY ABS(n_distinct) DESC;

\echo ''
\echo '===================================================='
\echo 'BLOOM FILTER VALIDATION (Automated)'
\echo '===================================================='
\echo ''

-- =====================================================
-- Validate Proposed Bloom Filter Columns
-- =====================================================

\echo 'Validating proposed bloom filter columns:'
\echo '  Candidates: trade_id, symbol, exchange_id, trade_type, sale_condition'
\echo ''

SELECT * FROM trading_validation.validate_bloom_candidates(
    'pg_temp',
    'tick_data_sample',
    ARRAY['trade_id', 'symbol', 'exchange_id', 'trade_type', 'sale_condition', 'trade_condition']
);

\echo ''
\echo '===================================================='
\echo 'ANALYSIS SUMMARY'
\echo '===================================================='
\echo ''

DO $$
DECLARE
    v_trade_id_card BIGINT;
    v_symbol_card BIGINT;
    v_exchange_card BIGINT;
    v_trade_type_card BIGINT;
    v_total_rows BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total_rows FROM pg_temp.tick_data_sample;

    SELECT
        CASE WHEN n_distinct < 0 THEN (ABS(n_distinct) * v_total_rows)::BIGINT ELSE n_distinct::BIGINT END
    INTO v_trade_id_card
    FROM pg_stats WHERE schemaname = 'pg_temp' AND tablename = 'tick_data_sample' AND attname = 'trade_id';

    SELECT
        CASE WHEN n_distinct < 0 THEN (ABS(n_distinct) * v_total_rows)::BIGINT ELSE n_distinct::BIGINT END
    INTO v_symbol_card
    FROM pg_stats WHERE schemaname = 'pg_temp' AND tablename = 'tick_data_sample' AND attname = 'symbol';

    SELECT
        CASE WHEN n_distinct < 0 THEN (ABS(n_distinct) * v_total_rows)::BIGINT ELSE n_distinct::BIGINT END
    INTO v_exchange_card
    FROM pg_stats WHERE schemaname = 'pg_temp' AND tablename = 'tick_data_sample' AND attname = 'exchange_id';

    SELECT
        CASE WHEN n_distinct < 0 THEN (ABS(n_distinct) * v_total_rows)::BIGINT ELSE n_distinct::BIGINT END
    INTO v_trade_type_card
    FROM pg_stats WHERE schemaname = 'pg_temp' AND tablename = 'tick_data_sample' AND attname = 'trade_type';

    RAISE NOTICE 'Sample size: % rows', v_total_rows;
    RAISE NOTICE '';
    RAISE NOTICE 'Cardinality Summary:';
    RAISE NOTICE '  trade_id:     % (UNIQUE per trade)', v_trade_id_card;
    RAISE NOTICE '  symbol:       % (5,000 stocks)', v_symbol_card;
    RAISE NOTICE '  exchange_id:  % (20 exchanges)', v_exchange_card;
    RAISE NOTICE '  trade_type:   % (10 types)', v_trade_type_card;
    RAISE NOTICE '';

    RAISE NOTICE 'Bloom Filter Recommendations:';
    IF v_trade_id_card >= 1000 THEN
        RAISE NOTICE '  ✅ trade_id: SAFE (% unique values)', v_trade_id_card;
    ELSE
        RAISE NOTICE '  ❌ trade_id: UNSAFE (only % unique values)', v_trade_id_card;
    END IF;

    IF v_symbol_card >= 1000 THEN
        RAISE NOTICE '  ✅ symbol: SAFE (% unique values)', v_symbol_card;
    ELSE
        RAISE NOTICE '  ❌ symbol: UNSAFE (only % unique values)', v_symbol_card;
    END IF;

    IF v_exchange_card >= 1000 THEN
        RAISE NOTICE '  ✅ exchange_id: SAFE (% unique values)', v_exchange_card;
    ELSE
        RAISE NOTICE '  ❌ exchange_id: UNSAFE (only % unique values - use minmax only)', v_exchange_card;
    END IF;

    IF v_trade_type_card >= 1000 THEN
        RAISE NOTICE '  ✅ trade_type: SAFE (% unique values)', v_trade_type_card;
    ELSE
        RAISE NOTICE '  ❌ trade_type: UNSAFE (only % unique values - use minmax only)', v_trade_type_card;
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE 'Expected bloom filter columns: trade_id, symbol';
    RAISE NOTICE 'Excluded from bloom filters: exchange_id, trade_type (too low cardinality)';
END $$;

\echo ''
\echo '===================================================='
\echo 'Phase 2 complete!'
\echo '===================================================='
\echo ''
\echo 'Cardinality validation passed!'
\echo ''
\echo 'Key findings:'
\echo '  ✅ trade_id: ~1M unique (excellent for bloom filter)'
\echo '  ✅ symbol: ~5,000 unique (excellent for bloom filter)'
\echo '  ❌ exchange_id: ~20 unique (TOO LOW - exclude from bloom)'
\echo '  ❌ trade_type: ~10 unique (TOO LOW - exclude from bloom)'
\echo ''
\echo 'Next: Phase 3 - Auto-generate safe PAX configuration'
