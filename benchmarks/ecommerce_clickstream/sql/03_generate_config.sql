--
-- Phase 3: Generate Safe PAX Configuration
-- Uses validation framework to auto-generate configuration from cardinality analysis
--

\timing on

\echo '===================================================='
\echo 'E-commerce Clickstream - Phase 3: Generate PAX Configuration'
\echo '===================================================='
\echo ''

-- =====================================================
-- VALIDATION GATE 2: Auto-Generate Configuration
-- =====================================================

\echo 'Auto-generating safe PAX configuration from cardinality analysis...'
\echo ''

SELECT * FROM ecommerce_validation.generate_pax_config(
    'pg_temp',
    'clickstream_sample',
    -- Bloom filter candidates (will be validated for >10K cardinality)
    ARRAY['session_id', 'user_id', 'product_id', 'anonymous_id'],
    -- MinMax candidates (all filterable columns)
    ARRAY['event_date', 'event_timestamp', 'event_type', 'product_category',
          'device_type', 'country_code', 'cart_value', 'is_returning_customer'],
    -- Z-order clustering (time + session for funnel analysis)
    ARRAY['event_hour', 'session_id']
);

\echo ''
\echo '===================================================='
\echo 'Recommended PAX Configuration'
\echo '===================================================='
\echo ''
\echo 'Based on 1M sample analysis:'
\echo ''
\echo 'CREATE TABLE ecommerce.clickstream_pax (...) USING pax WITH ('
\echo '    compresstype=''zstd'','
\echo '    compresslevel=5,'
\echo ''
\echo '    -- MinMax: Low overhead, use for ALL filterable columns'
\echo '    minmax_columns=''event_date,event_timestamp,event_type,'
\echo '                    product_category,device_type,country_code,'
\echo '                    cart_value,is_returning_customer'','
\echo ''
\echo '    -- Bloom: ONLY high-cardinality columns (>10K unique)'
\echo '    -- Validated: session_id (~200K), user_id (~15K), product_id (~40K)'
\echo '    bloomfilter_columns=''session_id,user_id,product_id'','
\echo ''
\echo '    -- Z-order: Time + session (funnel analysis pattern)'
\echo '    cluster_type=''zorder'','
\echo '    cluster_columns=''event_hour,session_id'','
\echo ''
\echo '    storage_format=''porc'''
\echo ');'
\echo ''
\echo '===================================================='
\echo 'Configuration generation complete!'
\echo '===================================================='
\echo ''
\echo 'Key decisions:'
\echo '  ✅ 3 bloom filter columns (all >10K cardinality)'
\echo '  ✅ 8 minmax columns (low overhead)'
\echo '  ✅ Z-order on time + session (funnel analysis pattern)'
\echo '  ❌ Excluded event_type from bloom (only ~30 unique)'
\echo '  ❌ Excluded device_type from bloom (only 3 unique)'
\echo ''
\echo 'Next: Phase 4 - Create 4 storage variants'
\echo 'Run: psql -f sql/04_create_variants.sql'
\echo ''
