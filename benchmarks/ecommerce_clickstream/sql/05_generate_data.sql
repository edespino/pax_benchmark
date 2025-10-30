--
-- Phase 5: Generate Clickstream Data
-- Populates all 4 variants with identical 10M events
-- Realistic e-commerce behavior with proper funnel distributions
--

\timing on

\echo '====================================================  '
\echo 'E-commerce Clickstream - Phase 5: Generate Data'
\echo '===================================================='
\echo ''
\echo 'Generating 10,000,000 clickstream events...'
\echo '  (This will take 3-5 minutes)'
\echo ''
\echo 'Key characteristics:'
\echo '  - ~2M sessions (avg 5 events per session)'
\echo '  - ~500K registered users (30% of events)'
\echo '  - ~100K products'
\echo '  - Realistic funnel: 40% page views, 20% product views, 2% purchases'
\echo '  - Sparse fields: product_id (60% NULL), user_id (70% NULL)'
\echo ''

-- =====================================================
-- Insert Data into All 4 Variants
-- Using INSERT INTO ... SELECT for efficiency
-- =====================================================

\echo 'Step 1/4: Populating AO variant...'

INSERT INTO ecommerce.clickstream_ao
SELECT
    -- Time dimension (7 days of events, ~16 events per second)
    timestamp '2025-10-23 00:00:00' + (gs * interval '0.06048 seconds') AS event_timestamp,
    (timestamp '2025-10-23 00:00:00' + (gs * interval '0.06048 seconds'))::DATE AS event_date,
    date_trunc('hour', timestamp '2025-10-23 00:00:00' + (gs * interval '0.06048 seconds')) AS event_hour,

    -- Session ID (~2M sessions, 5 events per session on average)
    -- Power law distribution: some sessions have 1 event, others have 20+
    'sess-' || md5((gs / CASE
        WHEN random() < 0.5 THEN 5    -- 50% have ~5 events
        WHEN random() < 0.8 THEN 2    -- 30% have ~2 events (bounces)
        ELSE 10                        -- 20% have ~10 events (engaged)
    END)::TEXT) AS session_id,

    -- User ID (~500K registered users, 30% of events have user_id)
    CASE
        WHEN random() < 0.7 THEN NULL  -- 70% anonymous
        ELSE 'user-' || lpad((1 + (CASE
            WHEN random() < 0.2 THEN (random() * 10000)::INT       -- 20% power users
            WHEN random() < 0.6 THEN 10000 + (random() * 90000)::INT  -- 40% regular
            ELSE 100000 + (random() * 400000)::INT                 -- 40% occasional
        END))::TEXT, 10, '0')
    END AS user_id,

    -- Anonymous ID (~3M anonymous visitors, power law distribution)
    'anon-' || md5((CASE
        WHEN random() < 0.3 THEN (random() * 10000)::INT         -- 30% hot (10K)
        WHEN random() < 0.7 THEN 10000 + (random() * 90000)::INT  -- 40% warm (100K)
        ELSE 100000 + (random() * 2900000)::INT                   -- 30% cold (3M)
    END)::TEXT) AS anonymous_id,

    -- Event type (30 types, realistic funnel distribution)
    CASE
        WHEN random() < 0.40 THEN 'page_view'           -- 40% page views
        WHEN random() < 0.60 THEN 'product_view'        -- 20% product views
        WHEN random() < 0.70 THEN 'product_list_view'   -- 10% list views
        WHEN random() < 0.75 THEN 'add_to_cart'         -- 5% add to cart
        WHEN random() < 0.77 THEN 'view_cart'           -- 2% view cart
        WHEN random() < 0.80 THEN 'search'              -- 3% search
        WHEN random() < 0.85 THEN 'filter_apply'        -- 5% filters
        WHEN random() < 0.88 THEN 'begin_checkout'      -- 3% checkout
        WHEN random() < 0.90 THEN 'purchase'            -- 2% purchase ✅
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
        ELSE 'prod-' || lpad((1 + (CASE
            WHEN random() < 0.3 THEN (random() * 1000)::INT        -- 30% bestsellers
            WHEN random() < 0.7 THEN 1000 + (random() * 9000)::INT  -- 40% popular
            ELSE 10000 + (random() * 90000)::INT                   -- 30% long-tail
        END))::TEXT, 8, '0')
    END AS product_id,

    -- Product name
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE 'Product ' || (1 + (random() * 99999)::INT)::TEXT
    END AS product_name,

    -- Product category (200 categories from dimension table)
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE
            CASE (random() * 19)::INT
                WHEN 0 THEN 'Electronics'
                WHEN 1 THEN 'Clothing'
                WHEN 2 THEN 'Home & Garden'
                WHEN 3 THEN 'Sports & Outdoors'
                WHEN 4 THEN 'Books & Media'
                WHEN 5 THEN 'Toys & Games'
                WHEN 6 THEN 'Health & Beauty'
                WHEN 7 THEN 'Automotive'
                WHEN 8 THEN 'Food & Grocery'
                WHEN 9 THEN 'Pet Supplies'
                WHEN 10 THEN 'Office Supplies'
                WHEN 11 THEN 'Tools & Hardware'
                WHEN 12 THEN 'Baby & Kids'
                WHEN 13 THEN 'Jewelry & Accessories'
                WHEN 14 THEN 'Arts & Crafts'
                WHEN 15 THEN 'Musical Instruments'
                WHEN 16 THEN 'Fitness Equipment'
                WHEN 17 THEN 'Outdoor Living'
                WHEN 18 THEN 'Party Supplies'
                ELSE 'Industrial & Scientific'
            END
    END AS product_category,

    -- Product price ($5-$500, log-normal distribution)
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE ROUND((5 + CASE
            WHEN random() < 0.7 THEN random() * 95      -- 70% under $100
            WHEN random() < 0.9 THEN 100 + random() * 150  -- 20% $100-$250
            ELSE 250 + random() * 250                     -- 10% $250-$500
        END)::NUMERIC, 2)
    END AS product_price,

    -- Product quantity
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE (1 + (CASE
            WHEN random() < 0.8 THEN (random() * 1)::INT  -- 80% buy 1
            WHEN random() < 0.95 THEN (random() * 2)::INT  -- 15% buy 2-3
            ELSE (random() * 7)::INT                       -- 5% buy 4-10
        END))
    END AS product_quantity,

    -- Cart value ($10-$1000)
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE ROUND((10 + CASE
            WHEN random() < 0.6 THEN random() * 90      -- 60% under $100
            WHEN random() < 0.9 THEN 100 + random() * 200  -- 30% $100-$300
            ELSE 300 + random() * 700                     -- 10% $300-$1000
        END)::NUMERIC, 2)
    END AS cart_value,

    -- Cart item count
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE (1 + (CASE
            WHEN random() < 0.7 THEN (random() * 2)::INT  -- 70% have 1-3 items
            WHEN random() < 0.9 THEN (random() * 5)::INT  -- 20% have 4-8 items
            ELSE (random() * 12)::INT                      -- 10% have 9-20 items
        END))
    END AS cart_item_count,

    -- User segment (20 segments, only for registered users)
    CASE
        WHEN random() < 0.7 THEN NULL  -- Anonymous users
        ELSE
            CASE (random() * 19)::INT
                WHEN 0 THEN 'high-value'
                WHEN 1 THEN 'medium-value'
                WHEN 2 THEN 'low-value'
                WHEN 3 THEN 'new-customer'
                WHEN 4 THEN 'repeat-buyer'
                WHEN 5 THEN 'at-risk'
                WHEN 6 THEN 'champion'
                WHEN 7 THEN 'loyal'
                WHEN 8 THEN 'window-shopper'
                WHEN 9 THEN 'bargain-hunter'
                WHEN 10 THEN 'impulse-buyer'
                WHEN 11 THEN 'researcher'
                WHEN 12 THEN 'mobile-first'
                WHEN 13 THEN 'desktop-user'
                WHEN 14 THEN 'early-adopter'
                WHEN 15 THEN 'brand-loyal'
                WHEN 16 THEN 'price-sensitive'
                WHEN 17 THEN 'quality-seeker'
                WHEN 18 THEN 'gift-buyer'
                ELSE 'seasonal-shopper'
            END
    END AS user_segment,

    -- Is returning customer (only for registered users)
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE random() < 0.4  -- 40% returning among registered
    END AS is_returning_customer,

    -- Lifetime value bucket
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

    -- Browser (20 browsers, Chrome dominant)
    CASE
        WHEN random() < 0.45 THEN 'Chrome'
        WHEN random() < 0.60 THEN 'Safari'
        WHEN random() < 0.70 THEN 'Firefox'
        WHEN random() < 0.80 THEN 'Edge'
        WHEN random() < 0.85 THEN 'Opera'
        WHEN random() < 0.90 THEN 'Samsung Internet'
        ELSE 'Other-' || (6 + (random() * 13)::INT)::TEXT
    END AS browser,

    -- OS (15 operating systems)
    CASE
        WHEN random() < 0.35 THEN 'iOS'
        WHEN random() < 0.60 THEN 'Android'
        WHEN random() < 0.75 THEN 'Windows'
        WHEN random() < 0.85 THEN 'MacOS'
        WHEN random() < 0.90 THEN 'Linux'
        ELSE 'Other-OS-' || (5 + (random() * 9)::INT)::TEXT
    END AS os,

    -- Screen resolution (50 resolutions)
    CASE
        WHEN random() < 0.25 THEN '1920x1080'
        WHEN random() < 0.40 THEN '1366x768'
        WHEN random() < 0.55 THEN '375x667'
        WHEN random() < 0.70 THEN '414x896'
        WHEN random() < 0.80 THEN '360x640'
        ELSE 'res-' || (6 + (random() * 43)::INT)::TEXT
    END AS screen_resolution,

    -- UTM source (100 sources, 40% organic/direct)
    CASE
        WHEN random() < 0.4 THEN NULL  -- Organic/direct
        ELSE
            CASE
                WHEN random() < 0.30 THEN 'google'
                WHEN random() < 0.50 THEN 'facebook'
                WHEN random() < 0.65 THEN 'instagram'
                WHEN random() < 0.75 THEN 'email'
                WHEN random() < 0.82 THEN 'tiktok'
                WHEN random() < 0.88 THEN 'twitter'
                WHEN random() < 0.92 THEN 'pinterest'
                WHEN random() < 0.96 THEN 'youtube'
                ELSE 'source-' || (8 + (random() * 91)::INT)::TEXT
            END
    END AS utm_source,

    -- UTM medium (30 mediums)
    CASE
        WHEN random() < 0.4 THEN NULL
        ELSE
            CASE
                WHEN random() < 0.40 THEN 'cpc'
                WHEN random() < 0.70 THEN 'social'
                WHEN random() < 0.85 THEN 'email'
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

    -- Country code (200 countries, US-dominant)
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

    -- Experiment ID (~100 A/B tests, 30% in experiments)
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE 'exp-' || lpad((1 + (random() * 99)::INT)::TEXT, 3, '0')
    END AS experiment_id,

    -- Variant ID (~300 variants)
    CASE
        WHEN random() < 0.7 THEN NULL
        ELSE 'var-' || lpad((1 + (random() * 299)::INT)::TEXT, 3, '0')
    END AS variant_id,

    -- Personalization segment (~50 segments, 40% personalized)
    CASE
        WHEN random() < 0.6 THEN NULL
        ELSE 'pers-seg-' || (1 + (random() * 49)::INT)::TEXT
    END AS personalization_segment,

    -- Event value (10% of events have explicit value)
    CASE
        WHEN random() < 0.9 THEN NULL
        ELSE ROUND((1 + random() * 999)::NUMERIC, 2)
    END AS event_value,

    -- Sequence in session (1-50)
    (gs % 50) + 1 AS sequence_in_session,

    -- Time on page (0-600 seconds, exponential decay)
    (CASE
        WHEN random() < 0.5 THEN random() * 30       -- 50% under 30 sec
        WHEN random() < 0.8 THEN 30 + random() * 90  -- 30% 30-120 sec
        ELSE 120 + random() * 480                     -- 20% 2-10 min
    END)::INT AS time_on_page_seconds

FROM generate_series(1, 10000000) gs;

\echo '  ✓ AO populated (10M events)'
\echo ''

-- =====================================================

\echo 'Step 2/4: Populating AOCO variant...'

INSERT INTO ecommerce.clickstream_aoco
SELECT * FROM ecommerce.clickstream_ao;

\echo '  ✓ AOCO populated (10M events)'
\echo ''

-- =====================================================

\echo 'Step 3/4: Populating PAX (clustered) variant...'

INSERT INTO ecommerce.clickstream_pax
SELECT * FROM ecommerce.clickstream_ao;

\echo '  ✓ PAX clustered populated (10M events)'
\echo ''

-- =====================================================

\echo 'Step 4/4: Populating PAX (no-cluster) variant...'

INSERT INTO ecommerce.clickstream_pax_nocluster
SELECT * FROM ecommerce.clickstream_ao;

\echo '  ✓ PAX no-cluster populated (10M events)'
\echo ''

-- =====================================================
-- ANALYZE All Tables
-- =====================================================

\echo 'Running ANALYZE on all variants...'

ANALYZE ecommerce.clickstream_ao;
ANALYZE ecommerce.clickstream_aoco;
ANALYZE ecommerce.clickstream_pax;
ANALYZE ecommerce.clickstream_pax_nocluster;

\echo '  ✓ ANALYZE complete'
\echo ''

-- =====================================================
-- Summary
-- =====================================================

\echo 'Data generation summary:'
\echo ''

SELECT
    tablename AS variant,
    CASE
        WHEN tablename = 'clickstream_ao' THEN 'AO'
        WHEN tablename = 'clickstream_aoco' THEN 'AOCO'
        WHEN tablename = 'clickstream_pax' THEN 'PAX (clustered)'
        WHEN tablename = 'clickstream_pax_nocluster' THEN 'PAX (no-cluster)'
    END AS variant_name,
    (SELECT COUNT(*) FROM ecommerce.clickstream_ao) AS row_count,
    pg_size_pretty(pg_total_relation_size('ecommerce.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size('ecommerce.' || tablename)) AS table_size
FROM pg_tables
WHERE schemaname = 'ecommerce'
  AND tablename LIKE 'clickstream_%'
ORDER BY tablename;

\echo ''
\echo '===================================================='
\echo 'Data generation complete!'
\echo '===================================================='
\echo ''
\echo 'Sparse field characteristics (expected):'
\echo '  - product_id: ~60% NULL (non-product events)'
\echo '  - user_id: ~70% NULL (anonymous sessions)'
\echo '  - utm_source/medium/campaign: ~40% NULL (organic traffic)'
\echo ''
\echo 'This demonstrates PAX sparse filtering and bloom filter effectiveness!'
\echo ''
\echo 'Next: Phase 6 - Optimize PAX with Z-order clustering'
\echo 'Run: psql -f sql/06_optimize_pax.sql'
\echo ''
