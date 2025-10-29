--
-- Phase 3: Generate Safe PAX Configuration
-- Auto-generates configuration from cardinality analysis
-- Prevents manual configuration errors
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 3: Generate Configuration'
\echo '===================================================='
\echo ''

-- Note: This requires cardinality analysis to have been run first
-- (sql/02_analyze_cardinality.sql)

\echo 'Generating auto-validated PAX configuration...'
\echo ''

-- Re-create sample table for config generation
-- (In real usage, this would be your actual source data)
CREATE TEMP TABLE tick_data_sample AS
SELECT
    timestamp '2025-10-29 09:30:00' + (gs * interval '1 millisecond' * (random() * 10)::INT) AS trade_timestamp,
    (timestamp '2025-10-29 09:30:00' + (gs * interval '1 millisecond' * (random() * 10)::INT))::DATE AS trade_date,
    date_trunc('second', timestamp '2025-10-29 09:30:00' + (gs * interval '1 millisecond' * (random() * 10)::INT)) AS trade_time_bucket,
    gs AS trade_id,
    s.symbol,
    s.exchange_id,
    (s.price_range_min + random() * (s.price_range_max - s.price_range_min))::NUMERIC(18,6) AS price,
    (100 + (random() * 10000)::INT) AS quantity,
    ((s.price_range_min + random() * (s.price_range_max - s.price_range_min)) * (100 + (random() * 10000)::INT))::NUMERIC(20,2) AS volume_usd,
    (s.price_range_min + random() * (s.price_range_max - s.price_range_min) * 0.998)::NUMERIC(18,6) AS bid_price,
    (s.price_range_min + random() * (s.price_range_max - s.price_range_min) * 1.002)::NUMERIC(18,6) AS ask_price,
    (100 + (random() * 5000)::INT) AS bid_size,
    (100 + (random() * 5000)::INT) AS ask_size,
    (ARRAY['market','limit','stop','stop_limit','iceberg','fill_or_kill','immediate_or_cancel','all_or_none','market_on_close','limit_on_close'])[1 + (random() * 9)::INT] AS trade_type,
    CASE WHEN random() < 0.40 THEN 'institutional' WHEN random() < 0.75 THEN 'retail' WHEN random() < 0.90 THEN 'market_maker' WHEN random() < 0.95 THEN 'algorithmic' ELSE 'high_frequency' END AS buyer_type,
    CASE WHEN random() < 0.40 THEN 'institutional' WHEN random() < 0.75 THEN 'retail' WHEN random() < 0.90 THEN 'market_maker' WHEN random() < 0.95 THEN 'algorithmic' ELSE 'high_frequency' END AS seller_type,
    (ARRAY['@','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','1','2','3','4','5','6','7','8','9','A1','A2','B1','B2','C1','C2','D1','D2','E1','E2','F1','F2','G1','G2','H1','H2'])[1 + (random() * 49)::INT] AS trade_condition,
    (ARRAY['REGULAR','CASH','NEXT_DAY','SELLER','SPECIAL_TERMS','WHEN_ISSUED','OPENING','CLOSING','CONTINGENT','AVERAGE_PRICE'])[1 + (random() * 9)::INT] AS sale_condition,
    ((random() - 0.5) * 100)::NUMERIC(10,4) AS price_change_bps,
    (random() < 0.05) AS is_block_trade,
    gs AS sequence_number,
    md5(gs::TEXT || random()::TEXT) AS checksum
FROM generate_series(1, 100000) gs
CROSS JOIN LATERAL (
    SELECT symbol, exchange_id, price_range_min, price_range_max
    FROM trading.symbols
    WHERE is_active = true
    OFFSET (random() * 4999)::INT
    LIMIT 1
) s;

ANALYZE tick_data_sample;

\echo '  ✓ Sample data created for configuration generation'
\echo ''

-- =====================================================
-- Generate Configuration
-- =====================================================

\echo '===================================================='
\echo 'AUTO-GENERATED PAX CONFIGURATION'
\echo '===================================================='
\echo ''

SELECT trading_validation.generate_pax_config(
    'pg_temp',              -- Schema containing sample table
    'tick_data_sample',     -- Sample table name
    10000000,               -- Target rows for production table
    'trade_time_bucket,symbol'  -- Z-order clustering columns (TIMESTAMP + VARCHAR supported)
);

\echo ''
\echo '===================================================='
\echo ''

-- =====================================================
-- Validation Summary
-- =====================================================

\echo 'Configuration generation complete!'
\echo ''
\echo 'The auto-generated configuration above:'
\echo '  ✅ Only includes bloom filters on high-cardinality columns (>=1000 unique)'
\echo '  ✅ Includes minmax statistics on filterable columns (>=10 unique)'
\echo '  ✅ Calculates correct maintenance_work_mem for 10M rows'
\echo '  ✅ Prevents the 81% storage bloat from low-cardinality bloom filters'
\echo ''
\echo 'Expected bloom filter columns: trade_id, symbol'
\echo 'Excluded from bloom filters: exchange_id (~20), trade_type (~10)'
\echo ''
\echo 'Copy the configuration above to create your PAX tables safely.'
\echo ''
\echo 'Next: Phase 4 - Create storage variants with validated configuration'

-- Cleanup
DROP TABLE IF EXISTS tick_data_sample;
