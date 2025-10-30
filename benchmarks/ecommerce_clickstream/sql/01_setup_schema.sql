--
-- Phase 1: E-commerce Clickstream Schema Setup
-- Creates schema and dimension tables for clickstream benchmark
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 1: Schema Setup'
\echo '===================================================='
\echo ''

-- Drop and recreate schema
DROP SCHEMA IF EXISTS ecommerce CASCADE;
CREATE SCHEMA ecommerce;

\echo 'Creating dimension tables...'
\echo ''

-- =====================================================
-- Event Types Dimension
-- =====================================================

CREATE TABLE ecommerce.event_types (
    event_type VARCHAR(50) PRIMARY KEY,
    event_category VARCHAR(50),
    description TEXT
) DISTRIBUTED REPLICATED;

INSERT INTO ecommerce.event_types VALUES
    ('page_view', 'navigation', 'User viewed a page'),
    ('product_view', 'product', 'User viewed product details'),
    ('product_list_view', 'product', 'User viewed product listing'),
    ('search', 'navigation', 'User performed search'),
    ('search_results', 'navigation', 'Search results displayed'),
    ('add_to_cart', 'cart', 'User added item to cart'),
    ('remove_from_cart', 'cart', 'User removed item from cart'),
    ('update_cart', 'cart', 'User updated cart quantity'),
    ('view_cart', 'cart', 'User viewed shopping cart'),
    ('begin_checkout', 'checkout', 'User started checkout process'),
    ('add_shipping_info', 'checkout', 'User entered shipping info'),
    ('add_payment_info', 'checkout', 'User entered payment info'),
    ('purchase', 'conversion', 'User completed purchase'),
    ('refund', 'conversion', 'Purchase refunded'),
    ('signup', 'user', 'User created account'),
    ('login', 'user', 'User logged in'),
    ('logout', 'user', 'User logged out'),
    ('profile_view', 'user', 'User viewed their profile'),
    ('profile_update', 'user', 'User updated profile'),
    ('wishlist_add', 'engagement', 'User added to wishlist'),
    ('wishlist_remove', 'engagement', 'User removed from wishlist'),
    ('review_submit', 'engagement', 'User submitted product review'),
    ('review_view', 'engagement', 'User viewed reviews'),
    ('share', 'engagement', 'User shared product/page'),
    ('email_signup', 'marketing', 'User signed up for emails'),
    ('coupon_applied', 'marketing', 'User applied coupon code'),
    ('promo_click', 'marketing', 'User clicked promotion'),
    ('banner_click', 'marketing', 'User clicked banner ad'),
    ('filter_apply', 'navigation', 'User applied product filter'),
    ('sort_change', 'navigation', 'User changed sort order');

\echo '  ✓ event_types created (30 types)'

-- =====================================================
-- Product Categories Dimension
-- =====================================================

CREATE TABLE ecommerce.product_categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) UNIQUE NOT NULL,
    parent_category VARCHAR(100),
    level INTEGER
) DISTRIBUTED REPLICATED;

-- Generate 200 product categories (hierarchical)
INSERT INTO ecommerce.product_categories (category_name, parent_category, level)
SELECT
    CASE
        -- Top-level categories (20)
        WHEN gs <= 20 THEN
            CASE (gs - 1) % 20
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
        -- Sub-categories (180)
        ELSE
            CASE ((gs - 21) % 20)
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
            END || ' > Sub-' || lpad(((gs - 21) / 20 + 1)::TEXT, 2, '0')
    END AS category_name,
    CASE
        WHEN gs <= 20 THEN NULL
        ELSE
            CASE ((gs - 21) % 20)
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
    END AS parent_category,
    CASE WHEN gs <= 20 THEN 1 ELSE 2 END AS level
FROM generate_series(1, 200) gs;

\echo '  ✓ product_categories created (200 categories, 2 levels)'

-- =====================================================
-- User Segments Dimension
-- =====================================================

CREATE TABLE ecommerce.user_segments (
    segment_name VARCHAR(50) PRIMARY KEY,
    segment_type VARCHAR(50),
    description TEXT
) DISTRIBUTED REPLICATED;

INSERT INTO ecommerce.user_segments VALUES
    ('high-value', 'value', 'High lifetime value customers'),
    ('medium-value', 'value', 'Medium lifetime value customers'),
    ('low-value', 'value', 'Low lifetime value customers'),
    ('new-customer', 'lifecycle', 'First-time customers'),
    ('repeat-buyer', 'lifecycle', 'Repeat purchasers'),
    ('at-risk', 'lifecycle', 'Inactive customers'),
    ('champion', 'behavior', 'Best customers'),
    ('loyal', 'behavior', 'Consistent purchasers'),
    ('window-shopper', 'behavior', 'Browsers, rare buyers'),
    ('bargain-hunter', 'behavior', 'Buys on discount only'),
    ('impulse-buyer', 'behavior', 'Quick purchase decisions'),
    ('researcher', 'behavior', 'Extensive comparison'),
    ('mobile-first', 'device', 'Primarily mobile users'),
    ('desktop-user', 'device', 'Primarily desktop users'),
    ('early-adopter', 'product', 'Buys new products'),
    ('brand-loyal', 'product', 'Sticks to brands'),
    ('price-sensitive', 'product', 'Price-driven decisions'),
    ('quality-seeker', 'product', 'Premium products'),
    ('gift-buyer', 'occasion', 'Frequent gift purchases'),
    ('seasonal-shopper', 'occasion', 'Holiday shoppers');

\echo '  ✓ user_segments created (20 segments)'

-- =====================================================
-- Marketing Campaigns Dimension
-- =====================================================

CREATE TABLE ecommerce.marketing_campaigns (
    campaign_id SERIAL PRIMARY KEY,
    campaign_name VARCHAR(100) UNIQUE NOT NULL,
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    campaign_type VARCHAR(50)
) DISTRIBUTED REPLICATED;

-- Generate 500 marketing campaigns
INSERT INTO ecommerce.marketing_campaigns (campaign_name, utm_source, utm_medium, campaign_type)
SELECT
    'campaign-' || lpad(gs::TEXT, 4, '0') AS campaign_name,
    CASE (gs % 10)
        WHEN 0 THEN 'google'
        WHEN 1 THEN 'facebook'
        WHEN 2 THEN 'instagram'
        WHEN 3 THEN 'email'
        WHEN 4 THEN 'tiktok'
        WHEN 5 THEN 'twitter'
        WHEN 6 THEN 'pinterest'
        WHEN 7 THEN 'youtube'
        WHEN 8 THEN 'reddit'
        ELSE 'organic'
    END AS utm_source,
    CASE (gs % 5)
        WHEN 0 THEN 'cpc'
        WHEN 1 THEN 'social'
        WHEN 2 THEN 'email'
        WHEN 3 THEN 'display'
        ELSE 'organic'
    END AS utm_medium,
    CASE (gs % 6)
        WHEN 0 THEN 'seasonal'
        WHEN 1 THEN 'product-launch'
        WHEN 2 THEN 'brand-awareness'
        WHEN 3 THEN 'retargeting'
        WHEN 4 THEN 'loyalty'
        ELSE 'general'
    END AS campaign_type
FROM generate_series(1, 500) gs;

\echo '  ✓ marketing_campaigns created (500 campaigns)'

-- =====================================================
-- Summary
-- =====================================================

\echo ''
\echo '===================================================='
\echo 'Schema setup complete!'
\echo '===================================================='
\echo ''

SELECT
    'Dimension Tables' AS summary_type,
    COUNT(*) AS table_count
FROM pg_tables
WHERE schemaname = 'ecommerce'
  AND tablename != 'clickstream'
UNION ALL
SELECT
    'Event Types' AS summary_type,
    COUNT(*)::BIGINT AS table_count
FROM ecommerce.event_types
UNION ALL
SELECT
    'Product Categories' AS summary_type,
    COUNT(*)::BIGINT AS table_count
FROM ecommerce.product_categories
UNION ALL
SELECT
    'User Segments' AS summary_type,
    COUNT(*)::BIGINT AS table_count
FROM ecommerce.user_segments
UNION ALL
SELECT
    'Marketing Campaigns' AS summary_type,
    COUNT(*)::BIGINT AS table_count
FROM ecommerce.marketing_campaigns;

\echo ''
\echo 'Next: Phase 2 - Cardinality analysis'
\echo 'Run: psql -f sql/02_analyze_cardinality.sql'
\echo ''
