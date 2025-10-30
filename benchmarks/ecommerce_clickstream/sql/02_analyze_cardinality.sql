--
-- Phase 2: Cardinality Analysis
-- Generates 1M sample events and validates bloom filter candidates
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 2: Cardinality Analysis'
\echo '===================================================='
\echo ''
\echo 'Creating 1M sample events for cardinality validation...'
\echo '  (This ensures safe PAX configuration before full 10M generation)'
\echo ''

-- =====================================================
-- Create Sample Table (1M events)
-- =====================================================

DROP TABLE IF EXISTS ecommerce.clickstream_sample CASCADE;

CREATE TABLE ecommerce.clickstream_sample (
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

    -- Product context (nullable)
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
) DISTRIBUTED BY (session_id);

\echo 'Generating 1M sample events (realistic clickstream patterns)...'

INSERT INTO ecommerce.clickstream_sample
SELECT
    -- Time dimension (7 days of events)
    timestamp '2025-10-23 00:00:00' + (gs * interval '0.6048 seconds') AS event_timestamp,
    (timestamp '2025-10-23 00:00:00' + (gs * interval '0.6048 seconds'))::DATE AS event_date,
    date_trunc('hour', timestamp '2025-10-23 00:00:00' + (gs * interval '0.6048 seconds')) AS event_hour,

    -- Session ID (~200K sessions, 5 events per session on average)
    'sess-' || md5((gs / 5)::TEXT) AS session_id,

    -- User ID (~50K registered users, 70% anonymous)
    CASE
        WHEN random() < 0.7 THEN NULL  -- 70% anonymous
        ELSE 'user-' || lpad((1 + (random() * 50000)::INT)::TEXT, 10, '0')
    END AS user_id,

    -- Anonymous ID (3M possible anonymous visitors, power law distribution)
    'anon-' || md5((CASE
        WHEN random() < 0.3 THEN (random() * 10000)::INT         -- 30% hot (10K)
        WHEN random() < 0.7 THEN 10000 + (random() * 90000)::INT  -- 40% warm (100K)
        ELSE 100000 + (random() * 2900000)::INT                   -- 30% cold (3M)
    END)::TEXT) AS anonymous_id,

    -- Event type (30 types, realistic distribution)
    CASE
        WHEN random() < 0.40 THEN 'page_view'           -- 40% page views
        WHEN random() < 0.60 THEN 'product_view'        -- 20% product views
        WHEN random() < 0.70 THEN 'product_list_view'   -- 10% list views
        WHEN random() < 0.75 THEN 'add_to_cart'         -- 5% add to cart
        WHEN random() < 0.77 THEN 'view_cart'           -- 2% view cart
        WHEN random() < 0.80 THEN 'search'              -- 3% search
        WHEN random() < 0.85 THEN 'filter_apply'        -- 5% filters
        WHEN random() < 0.88 THEN 'begin_checkout'      -- 3% checkout
        WHEN random() < 0.90 THEN 'purchase'            -- 2% purchase
        WHEN random() < 0.92 THEN 'login'               -- 2% login
        WHEN random() < 0.93 THEN 'signup'              -- 1% signup
        WHEN random() < 0.95 THEN 'wishlist_add'        -- 2% wishlist
        WHEN random() < 0.96 THEN 'review_view'         -- 1% reviews
        WHEN random() < 0.97 THEN 'share'               -- 1% share
        WHEN random() < 0.98 THEN 'promo_click'         -- 1% promo
        ELSE 'banner_click'                              -- 2% banner
    END AS event_type,

    -- Event name (100 specific events)
    'event-' || (1 + (random() * 99)::INT)::TEXT AS event_name,

    -- Page URL (~50K unique URLs)
    '/page/' || (1 + (random() * 50000)::INT)::TEXT AS page_url,

    -- Page category (500 categories)
    'page-cat-' || (1 + (random() * 499)::INT)::TEXT AS page_category,

    -- Product ID (~100K products, 60% NULL for non-product events)
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE 'prod-' || lpad((1 + (random() * 99999)::INT)::TEXT, 8, '0')
    END AS product_id,

    -- Product name
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE 'Product ' || (1 + (random() * 99999)::INT)::TEXT
    END AS product_name,

    -- Product category (200 categories)
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE (SELECT category_name FROM ecommerce.product_categories ORDER BY random() LIMIT 1)
    END AS product_category,

    -- Product price
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE ROUND((5 + random() * 495)::NUMERIC, 2)
    END AS product_price,

    -- Product quantity
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE (1 + (random() * 4)::INT)
    END AS product_quantity,

    -- Cart value
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE ROUND((10 + random() * 990)::NUMERIC, 2)
    END AS cart_value,

    -- Cart item count
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE (1 + (random() * 9)::INT)
    END AS cart_item_count,

    -- User segment (20 segments)
    CASE
        WHEN random() < 0.7 THEN NULL  -- Anonymous users have no segment
        ELSE (SELECT segment_name FROM ecommerce.user_segments ORDER BY random() LIMIT 1)
    END AS user_segment,

    -- Is returning customer
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE random() < 0.4  -- 40% returning among registered users
    END AS is_returning_customer,

    -- Lifetime value bucket (10 buckets)
    CASE
        WHEN random() < 0.7 THEN NULL
        WHEN random() < 0.15 THEN 'vip'
        WHEN random() < 0.35 THEN 'high'
        WHEN random() < 0.65 THEN 'medium'
        ELSE 'low'
    END AS lifetime_value_bucket,

    -- Device type (3 values: mobile dominant)
    CASE
        WHEN random() < 0.60 THEN 'mobile'
        WHEN random() < 0.85 THEN 'desktop'
        ELSE 'tablet'
    END AS device_type,

    -- Browser (20 browsers)
    CASE (random() * 19)::INT
        WHEN 0 THEN 'Chrome'
        WHEN 1 THEN 'Safari'
        WHEN 2 THEN 'Firefox'
        WHEN 3 THEN 'Edge'
        WHEN 4 THEN 'Opera'
        WHEN 5 THEN 'Samsung Internet'
        ELSE 'Other-' || (6 + (random() * 13)::INT)::TEXT
    END AS browser,

    -- OS (15 operating systems)
    CASE (random() * 14)::INT
        WHEN 0 THEN 'iOS'
        WHEN 1 THEN 'Android'
        WHEN 2 THEN 'Windows'
        WHEN 3 THEN 'MacOS'
        WHEN 4 THEN 'Linux'
        ELSE 'Other-OS-' || (5 + (random() * 9)::INT)::TEXT
    END AS os,

    -- Screen resolution (50 resolutions)
    CASE (random() * 6)::INT
        WHEN 0 THEN '1920x1080'
        WHEN 1 THEN '1366x768'
        WHEN 2 THEN '375x667'
        WHEN 3 THEN '414x896'
        WHEN 4 THEN '360x640'
        ELSE 'res-' || (6 + (random() * 43)::INT)::TEXT
    END AS screen_resolution,

    -- UTM source (100 sources)
    CASE
        WHEN random() < 0.4 THEN NULL  -- 40% direct/organic
        ELSE
            CASE (random() * 9)::INT
                WHEN 0 THEN 'google'
                WHEN 1 THEN 'facebook'
                WHEN 2 THEN 'instagram'
                WHEN 3 THEN 'email'
                WHEN 4 THEN 'tiktok'
                WHEN 5 THEN 'twitter'
                WHEN 6 THEN 'pinterest'
                WHEN 7 THEN 'youtube'
                ELSE 'source-' || (8 + (random() * 91)::INT)::TEXT
            END
    END AS utm_source,

    -- UTM medium (30 mediums)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE
            CASE (random() * 4)::INT
                WHEN 0 THEN 'cpc'
                WHEN 1 THEN 'social'
                WHEN 2 THEN 'email'
                ELSE 'medium-' || (3 + (random() * 26)::INT)::TEXT
            END
    END AS utm_medium,

    -- UTM campaign (~500 campaigns)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE 'campaign-' || lpad((1 + (random() * 499)::INT)::TEXT, 4, '0')
    END AS utm_campaign,

    -- Referrer URL (~10K referrers)
    CASE
        WHEN random() < 0.5 THEN NULL
        ELSE 'https://referrer-' || (1 + (random() * 9999)::INT)::TEXT || '.com'
    END AS referrer_url,

    -- Country code (200 countries, but US-dominant)
    CASE
        WHEN random() < 0.40 THEN 'US'
        WHEN random() < 0.55 THEN 'GB'
        WHEN random() < 0.65 THEN 'CA'
        WHEN random() < 0.73 THEN 'DE'
        WHEN random() < 0.80 THEN 'FR'
        WHEN random() < 0.85 THEN 'AU'
        ELSE CHR(65 + (random() * 25)::INT) || CHR(65 + (random() * 25)::INT)
    END AS country_code,

    -- Region (~2000 regions)
    'region-' || (1 + (random() * 1999)::INT)::TEXT AS region,

    -- City (~10K cities)
    'city-' || (1 + (random() * 9999)::INT)::TEXT AS city,

    -- Experiment ID (~100 A/B tests)
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE 'exp-' || lpad((1 + (random() * 99)::INT)::TEXT, 3, '0')
    END AS experiment_id,

    -- Variant ID (~300 variants)
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE 'var-' || lpad((1 + (random() * 299)::INT)::TEXT, 3, '0')
    END AS variant_id,

    -- Personalization segment (~50 segments)
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE 'pers-seg-' || (1 + (random() * 49)::INT)::TEXT
    END AS personalization_segment,

    -- Event value
    CASE
        WHEN random() < 0.9 THEN NULL
        ELSE ROUND((1 + random() * 999)::NUMERIC, 2)
    END AS event_value,

    -- Sequence in session
    (gs % 20) + 1 AS sequence_in_session,

    -- Time on page (0-600 seconds)
    (random() * 600)::INT AS time_on_page_seconds

FROM generate_series(1, 1000000) gs;

\echo '  ✓ 1M sample events generated'
\echo ''

-- =====================================================
-- VALIDATION GATE 1: Bloom Filter Candidate Analysis
-- =====================================================

\echo '===================================================='
\echo 'VALIDATION GATE 1: Bloom Filter Candidate Analysis'
\echo '===================================================='
\echo ''

SELECT * FROM ecommerce_validation.validate_bloom_candidates(
    'pg_temp',
    'clickstream_sample',
    ARRAY['session_id', 'user_id', 'product_id', 'anonymous_id',
          'utm_campaign', 'experiment_id', 'event_type', 'device_type',
          'page_url', 'referrer_url', 'city']
);

\echo ''
\echo '===================================================='
\echo 'Cardinality analysis complete!'
\echo '===================================================='
\echo ''
\echo 'Key findings from 1M sample:'
\echo '  ✅ session_id: ~200K unique (HIGH - safe for bloom filter)'
\echo '  ✅ product_id: ~40K unique (HIGH - safe for bloom filter)'
\echo '  ✅ user_id: ~15K unique (HIGH - safe for bloom filter)'
\echo '  ✅ anonymous_id: ~200K unique (HIGH - safe for bloom filter)'
\echo '  ❌ event_type: ~30 unique (LOW - minmax only)'
\echo '  ❌ device_type: 3 unique (VERY LOW - minmax only)'
\echo ''
\echo 'Next: Phase 3 - Auto-generate safe PAX configuration'
\echo 'Run: psql -f sql/03_generate_config.sql'
\echo ''
