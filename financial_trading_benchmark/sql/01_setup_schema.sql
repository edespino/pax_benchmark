--
-- Phase 1: Trading Schema Setup
-- Creates stock exchange infrastructure and reference data
-- ~5,000 symbols, 20 exchanges
--

\timing on

\echo '===================================================='
\echo 'Financial Trading - Phase 1: Schema Setup'
\echo '===================================================='
\echo ''

-- Create schema
DROP SCHEMA IF EXISTS trading CASCADE;
CREATE SCHEMA trading;

\echo 'Trading schema created'
\echo ''

-- =====================================================
-- Dimension: Stock Exchanges
-- =====================================================

\echo 'Creating table: trading.exchanges'

CREATE TABLE trading.exchanges (
    exchange_id VARCHAR(10) PRIMARY KEY,
    exchange_name VARCHAR(100) NOT NULL,
    country_code VARCHAR(2) NOT NULL,
    timezone VARCHAR(50) NOT NULL,
    market_open_time TIME NOT NULL,
    market_close_time TIME NOT NULL,
    trading_days_per_year INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT now()
) DISTRIBUTED BY (exchange_id);

\echo '  ✓ trading.exchanges created'
\echo ''

-- =====================================================
-- Dimension: Stock Symbols
-- =====================================================

\echo 'Creating table: trading.symbols'

CREATE TABLE trading.symbols (
    symbol VARCHAR(10) PRIMARY KEY,
    company_name VARCHAR(200) NOT NULL,
    exchange_id VARCHAR(10) NOT NULL,
    sector VARCHAR(50) NOT NULL,
    industry VARCHAR(100) NOT NULL,
    market_cap_category VARCHAR(20) NOT NULL,  -- mega/large/mid/small/micro
    avg_daily_volume BIGINT NOT NULL,
    price_range_min NUMERIC(18,6) NOT NULL,
    price_range_max NUMERIC(18,6) NOT NULL,
    volatility_category VARCHAR(20) NOT NULL,  -- low/medium/high/extreme
    is_active BOOLEAN DEFAULT true,
    listing_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT now()
) DISTRIBUTED BY (symbol);

\echo '  ✓ trading.symbols created'
\echo ''

-- =====================================================
-- Populate Exchanges (20 global exchanges)
-- =====================================================

\echo 'Populating exchanges (20 global stock exchanges)...'

INSERT INTO trading.exchanges (exchange_id, exchange_name, country_code, timezone, market_open_time, market_close_time, trading_days_per_year) VALUES
('NYSE', 'New York Stock Exchange', 'US', 'America/New_York', '09:30', '16:00', 252),
('NASDAQ', 'NASDAQ Stock Market', 'US', 'America/New_York', '09:30', '16:00', 252),
('LSE', 'London Stock Exchange', 'GB', 'Europe/London', '08:00', '16:30', 252),
('JPX', 'Japan Exchange Group', 'JP', 'Asia/Tokyo', '09:00', '15:00', 245),
('SSE', 'Shanghai Stock Exchange', 'CN', 'Asia/Shanghai', '09:30', '15:00', 242),
('HKEX', 'Hong Kong Stock Exchange', 'HK', 'Asia/Hong_Kong', '09:30', '16:00', 249),
('EURONEXT', 'Euronext', 'EU', 'Europe/Paris', '09:00', '17:30', 252),
('TSX', 'Toronto Stock Exchange', 'CA', 'America/Toronto', '09:30', '16:00', 252),
('SZSE', 'Shenzhen Stock Exchange', 'CN', 'Asia/Shanghai', '09:30', '15:00', 242),
('BMV', 'Bolsa Mexicana de Valores', 'MX', 'America/Mexico_City', '08:30', '15:00', 250),
('B3', 'B3 Brasil Bolsa Balcão', 'BR', 'America/Sao_Paulo', '10:00', '17:00', 248),
('ASX', 'Australian Securities Exchange', 'AU', 'Australia/Sydney', '10:00', '16:00', 252),
('KOSPI', 'Korea Exchange', 'KR', 'Asia/Seoul', '09:00', '15:30', 248),
('TWSE', 'Taiwan Stock Exchange', 'TW', 'Asia/Taipei', '09:00', '13:30', 246),
('BSE', 'Bombay Stock Exchange', 'IN', 'Asia/Kolkata', '09:15', '15:30', 250),
('NSE', 'National Stock Exchange (India)', 'IN', 'Asia/Kolkata', '09:15', '15:30', 250),
('SGX', 'Singapore Exchange', 'SG', 'Asia/Singapore', '09:00', '17:00', 251),
('SIX', 'SIX Swiss Exchange', 'CH', 'Europe/Zurich', '09:00', '17:30', 252),
('JSE', 'Johannesburg Stock Exchange', 'ZA', 'Africa/Johannesburg', '09:00', '17:00', 252),
('MOEX', 'Moscow Exchange', 'RU', 'Europe/Moscow', '10:00', '18:50', 247);

\echo '  ✓ 20 exchanges inserted'
\echo ''

-- =====================================================
-- Populate Symbols (5,000 stocks with realistic distribution)
-- =====================================================

\echo 'Populating symbols (5,000 stocks across exchanges)...'

WITH
-- Exchange distribution (weighted towards major exchanges)
exchange_weights AS (
    SELECT 'NYSE' AS exchange_id, 0.25 AS weight UNION ALL
    SELECT 'NASDAQ', 0.20 UNION ALL
    SELECT 'LSE', 0.12 UNION ALL
    SELECT 'JPX', 0.10 UNION ALL
    SELECT 'SSE', 0.08 UNION ALL
    SELECT 'HKEX', 0.06 UNION ALL
    SELECT 'EURONEXT', 0.05 UNION ALL
    SELECT 'TSX', 0.04 UNION ALL
    SELECT 'SZSE', 0.03 UNION ALL
    SELECT 'ASX', 0.02 UNION ALL
    SELECT 'Others', 0.05  -- Remaining 10 exchanges
),
-- Sectors
sectors AS (
    SELECT 'Technology' AS sector, 0.20 AS weight UNION ALL
    SELECT 'Healthcare', 0.15 UNION ALL
    SELECT 'Financials', 0.15 UNION ALL
    SELECT 'Consumer Cyclical', 0.12 UNION ALL
    SELECT 'Industrials', 0.10 UNION ALL
    SELECT 'Consumer Defensive', 0.08 UNION ALL
    SELECT 'Energy', 0.07 UNION ALL
    SELECT 'Real Estate', 0.05 UNION ALL
    SELECT 'Utilities', 0.05 UNION ALL
    SELECT 'Materials', 0.03
),
-- Generate 5,000 symbols
symbol_gen AS (
    SELECT
        gs AS symbol_id,
        -- Generate symbol (e.g., AAPL, MSFT, etc.)
        CASE
            WHEN gs <= 26 THEN chr(65 + (gs - 1))
            WHEN gs <= 702 THEN chr(65 + ((gs - 27) / 26)) || chr(65 + ((gs - 27) % 26))
            WHEN gs <= 18278 THEN chr(65 + ((gs - 703) / 676)) || chr(65 + (((gs - 703) % 676) / 26)) || chr(65 + ((gs - 703) % 26))
            ELSE 'SYM' || lpad(gs::TEXT, 6, '0')
        END AS symbol,

        -- Assign exchange (weighted distribution)
        CASE
            WHEN (random() * 100)::INT < 25 THEN 'NYSE'
            WHEN (random() * 100)::INT < 45 THEN 'NASDAQ'
            WHEN (random() * 100)::INT < 57 THEN 'LSE'
            WHEN (random() * 100)::INT < 67 THEN 'JPX'
            WHEN (random() * 100)::INT < 75 THEN 'SSE'
            WHEN (random() * 100)::INT < 81 THEN 'HKEX'
            WHEN (random() * 100)::INT < 86 THEN 'EURONEXT'
            WHEN (random() * 100)::INT < 90 THEN 'TSX'
            WHEN (random() * 100)::INT < 93 THEN 'SZSE'
            WHEN (random() * 100)::INT < 95 THEN 'ASX'
            ELSE (ARRAY['BMV','B3','KOSPI','TWSE','BSE','NSE','SGX','SIX','JSE','MOEX'])[1 + (random() * 9)::INT]
        END AS exchange_id,

        -- Assign sector (weighted)
        CASE
            WHEN (random() * 100)::INT < 20 THEN 'Technology'
            WHEN (random() * 100)::INT < 35 THEN 'Healthcare'
            WHEN (random() * 100)::INT < 50 THEN 'Financials'
            WHEN (random() * 100)::INT < 62 THEN 'Consumer Cyclical'
            WHEN (random() * 100)::INT < 72 THEN 'Industrials'
            WHEN (random() * 100)::INT < 80 THEN 'Consumer Defensive'
            WHEN (random() * 100)::INT < 87 THEN 'Energy'
            WHEN (random() * 100)::INT < 92 THEN 'Real Estate'
            WHEN (random() * 100)::INT < 97 THEN 'Utilities'
            ELSE 'Materials'
        END AS sector,

        -- Market cap (Zipf distribution: few mega caps, many small caps)
        CASE
            WHEN random() < 0.02 THEN 'mega'       -- 2% mega cap (>$200B)
            WHEN random() < 0.10 THEN 'large'      -- 8% large cap ($10B-$200B)
            WHEN random() < 0.30 THEN 'mid'        -- 20% mid cap ($2B-$10B)
            WHEN random() < 0.70 THEN 'small'      -- 40% small cap ($300M-$2B)
            ELSE 'micro'                           -- 30% micro cap (<$300M)
        END AS market_cap_category,

        -- Volatility
        CASE
            WHEN random() < 0.60 THEN 'low'        -- 60% low volatility
            WHEN random() < 0.85 THEN 'medium'     -- 25% medium
            WHEN random() < 0.95 THEN 'high'       -- 10% high
            ELSE 'extreme'                         -- 5% extreme (penny stocks, etc)
        END AS volatility_category,

        random() AS rand1,
        random() AS rand2
    FROM generate_series(1, 5000) gs
)
INSERT INTO trading.symbols (
    symbol,
    company_name,
    exchange_id,
    sector,
    industry,
    market_cap_category,
    avg_daily_volume,
    price_range_min,
    price_range_max,
    volatility_category,
    listing_date
)
SELECT
    symbol,
    'Company ' || symbol AS company_name,
    exchange_id,
    sector,
    sector || ' - ' || (ARRAY['Services','Products','Equipment','Materials','Technology'])[1 + (rand1 * 4)::INT] AS industry,
    market_cap_category,
    -- Daily volume based on market cap
    CASE market_cap_category
        WHEN 'mega' THEN 10000000 + (rand1 * 50000000)::BIGINT
        WHEN 'large' THEN 1000000 + (rand1 * 10000000)::BIGINT
        WHEN 'mid' THEN 100000 + (rand1 * 1000000)::BIGINT
        WHEN 'small' THEN 10000 + (rand1 * 100000)::BIGINT
        ELSE 1000 + (rand1 * 10000)::BIGINT
    END AS avg_daily_volume,
    -- Price range based on market cap and volatility
    CASE market_cap_category
        WHEN 'mega' THEN (100 + rand1 * 400)::NUMERIC(18,6)
        WHEN 'large' THEN (50 + rand1 * 200)::NUMERIC(18,6)
        WHEN 'mid' THEN (20 + rand1 * 80)::NUMERIC(18,6)
        WHEN 'small' THEN (5 + rand1 * 30)::NUMERIC(18,6)
        ELSE (0.50 + rand1 * 10)::NUMERIC(18,6)
    END AS price_range_min,
    CASE market_cap_category
        WHEN 'mega' THEN (200 + rand2 * 800)::NUMERIC(18,6)
        WHEN 'large' THEN (80 + rand2 * 400)::NUMERIC(18,6)
        WHEN 'mid' THEN (35 + rand2 * 150)::NUMERIC(18,6)
        WHEN 'small' THEN (10 + rand2 * 50)::NUMERIC(18,6)
        ELSE (2 + rand2 * 20)::NUMERIC(18,6)
    END AS price_range_max,
    volatility_category,
    DATE '2020-01-01' - (rand1 * 3650)::INT AS listing_date
FROM symbol_gen;

\echo '  ✓ 5,000 symbols inserted'
\echo ''

-- Create indexes for reference data
CREATE INDEX idx_symbols_exchange ON trading.symbols(exchange_id);
CREATE INDEX idx_symbols_sector ON trading.symbols(sector);
CREATE INDEX idx_symbols_market_cap ON trading.symbols(market_cap_category);

\echo '  ✓ Indexes created'
\echo ''

-- =====================================================
-- Statistics
-- =====================================================

ANALYZE trading.exchanges;
ANALYZE trading.symbols;

\echo '===================================================='
\echo 'Schema Setup Summary'
\echo '===================================================='
\echo ''

SELECT 'Exchanges' AS dimension, COUNT(*) AS count, pg_size_pretty(pg_total_relation_size('trading.exchanges')) AS size
FROM trading.exchanges
UNION ALL
SELECT 'Symbols', COUNT(*), pg_size_pretty(pg_total_relation_size('trading.symbols'))
FROM trading.symbols;

\echo ''

-- Show distribution
\echo 'Symbol distribution by exchange:'
SELECT exchange_id, COUNT(*) AS symbol_count
FROM trading.symbols
GROUP BY exchange_id
ORDER BY symbol_count DESC
LIMIT 10;

\echo ''
\echo 'Symbol distribution by sector:'
SELECT sector, COUNT(*) AS symbol_count
FROM trading.symbols
GROUP BY sector
ORDER BY symbol_count DESC;

\echo ''
\echo 'Symbol distribution by market cap:'
SELECT market_cap_category, COUNT(*) AS symbol_count, ROUND(COUNT(*)::NUMERIC / 50, 1) AS percent
FROM trading.symbols
GROUP BY market_cap_category
ORDER BY symbol_count DESC;

\echo ''
\echo '===================================================='
\echo 'Phase 1 complete!'
\echo '===================================================='
\echo ''
\echo 'Reference data ready: 5,000 symbols across 20 exchanges'
\echo 'Next: Phase 2 - Cardinality analysis'
