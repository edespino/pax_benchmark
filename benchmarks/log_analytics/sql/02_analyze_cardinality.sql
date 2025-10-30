--
-- Phase 2: Analyze Cardinality (CRITICAL VALIDATION STEP)
-- Run BEFORE creating PAX tables to validate bloom filter candidates
-- This step prevents the 81% storage bloat discovered in October 2025
--

\timing on

\echo '===================================================='
\echo 'Log Analytics - Phase 2: Cardinality Analysis'
\echo '===================================================='
\echo ''
\echo '⚠️  CRITICAL: This validates bloom filter candidates'
\echo '⚠️  BEFORE table creation to prevent storage bloat'
\echo ''

-- =====================================================
-- Create Sample Table for Analysis
-- Use 1M row sample to get accurate statistics
-- =====================================================

\echo 'Step 1: Creating sample table for analysis...'
\echo '  (This will be dropped after analysis)'
\echo ''

DROP TABLE IF EXISTS logs.log_entries_sample CASCADE;

CREATE TEMP TABLE log_entries_sample AS
SELECT
    -- Time dimension
    timestamp '2025-10-01 00:00:00' + (gs * interval '0.1 seconds') AS log_timestamp,
    (timestamp '2025-10-01 00:00:00' + (gs * interval '0.1 seconds'))::DATE AS log_date,

    -- Application identifiers (MEDIUM CARDINALITY - 200 microservices)
    CASE (gs % 10)
        WHEN 0 THEN 'auth-service-'
        WHEN 1 THEN 'payment-api-'
        WHEN 2 THEN 'user-service-'
        WHEN 3 THEN 'product-catalog-'
        WHEN 4 THEN 'order-service-'
        WHEN 5 THEN 'inventory-api-'
        WHEN 6 THEN 'notification-worker-'
        WHEN 7 THEN 'analytics-processor-'
        WHEN 8 THEN 'search-service-'
        ELSE 'cache-manager-'
    END || lpad((gs % 20)::TEXT, 2, '0') AS application_id,

    -- Log level (VERY LOW CARDINALITY - 6 values)
    CASE
        WHEN random() < 0.01 THEN 'TRACE'
        WHEN random() < 0.10 THEN 'DEBUG'
        WHEN random() < 0.80 THEN 'INFO'    -- 80% INFO (realistic distribution)
        WHEN random() < 0.95 THEN 'WARN'    -- 15% WARN
        WHEN random() < 0.99 THEN 'ERROR'   -- 4% ERROR
        ELSE 'FATAL'                        -- 1% FATAL
    END AS log_level,

    -- Request identifiers (HIGH CARDINALITY - unique per request)
    'req-' || md5(gs::TEXT || random()::TEXT) AS request_id,
    'trace-' || md5(gs::TEXT) AS trace_id,

    -- User/session (HIGH CARDINALITY - millions of users)
    CASE
        WHEN random() < 0.3 THEN NULL  -- 30% anonymous/system logs
        ELSE 'user-' || lpad((1 + (random() * 5000000)::INT)::TEXT, 10, '0')
    END AS user_id,

    CASE
        WHEN random() < 0.3 THEN NULL  -- 30% no session
        ELSE 'sess-' || md5((gs / 1000)::TEXT || random()::TEXT)
    END AS session_id,

    -- Error information (SPARSE - only for ERROR/FATAL)
    CASE
        WHEN random() > 0.05 THEN NULL
        ELSE 'ERR-' || lpad((1 + (random() * 49)::INT)::TEXT, 4, '0')
    END AS error_code,

    CASE
        WHEN random() > 0.05 THEN NULL
        ELSE
            E'Exception at line ' || (100 + (random() * 900)::INT) || E'\n' ||
            '  at com.example.' ||
            CASE (random() * 5)::INT
                WHEN 0 THEN 'AuthService'
                WHEN 1 THEN 'DatabaseConnection'
                WHEN 2 THEN 'PaymentProcessor'
                WHEN 3 THEN 'CacheManager'
                ELSE 'MessageQueue'
            END ||
            '.process(Unknown Source)'
    END AS stack_trace,

    -- HTTP metadata (SPARSE for non-web services)
    CASE
        WHEN random() < 0.6 THEN
            CASE (random() * 10)::INT
                WHEN 0 THEN 'GET'
                WHEN 1 THEN 'POST'
                WHEN 2 THEN 'PUT'
                WHEN 3 THEN 'DELETE'
                WHEN 4 THEN 'PATCH'
                ELSE NULL
            END
        ELSE NULL
    END AS http_method,

    CASE
        WHEN random() < 0.6 THEN
            '/api/v1/' ||
            CASE (random() * 5)::INT
                WHEN 0 THEN 'users'
                WHEN 1 THEN 'products'
                WHEN 2 THEN 'orders'
                WHEN 3 THEN 'payments'
                ELSE 'search'
            END
        ELSE NULL
    END AS http_path,

    CASE
        WHEN random() < 0.6 THEN
            CASE
                WHEN random() < 0.85 THEN 200 + (random() * 7)::INT  -- 2xx responses
                WHEN random() < 0.92 THEN 400 + (random() * 5)::INT  -- 4xx errors
                ELSE 500 + (random() * 4)::INT                       -- 5xx errors
            END
        ELSE NULL
    END AS http_status_code,

    CASE
        WHEN random() < 0.6 THEN (10 + random() * 5000)::INTEGER
        ELSE NULL
    END AS response_time_ms,

    -- Message (always present)
    CASE
        WHEN random() < 0.80 THEN 'Request processed successfully'
        WHEN random() < 0.95 THEN 'Resource not found or access denied'
        ELSE 'Internal server error occurred during processing'
    END AS message,

    -- Environment/location (LOW-MEDIUM CARDINALITY)
    CASE (gs % 3)
        WHEN 0 THEN 'production'
        WHEN 1 THEN 'staging'
        ELSE 'development'
    END AS environment,

    CASE (gs % 6)
        WHEN 0 THEN 'us-east-1'
        WHEN 1 THEN 'us-west-2'
        WHEN 2 THEN 'eu-west-1'
        WHEN 3 THEN 'eu-central-1'
        WHEN 4 THEN 'ap-southeast-1'
        ELSE 'ap-northeast-1'
    END AS region,

    'host-' || lpad((1 + (gs % 500))::TEXT, 4, '0') AS hostname,

    -- Metadata
    gs AS sequence_number

FROM generate_series(1, 1000000) gs;

\echo '  ✓ Sample table created (1M rows)'
\echo ''

-- =====================================================
-- Step 2: ANALYZE to Collect Statistics
-- =====================================================

\echo 'Step 2: Running ANALYZE to collect statistics...'

ANALYZE log_entries_sample;

\echo '  ✓ Statistics collected'
\echo ''

-- =====================================================
-- Step 3: Validate ALL Proposed Bloom Filter Columns
-- =====================================================

\echo '===================================================='
\echo 'BLOOM FILTER CANDIDATE VALIDATION'
\echo '===================================================='
\echo ''
\echo 'Proposed bloom filter columns for validation:'
\echo '  - trace_id (expected: HIGH cardinality - ~1M unique)'
\echo '  - request_id (expected: HIGH cardinality - ~1M unique)'
\echo '  - user_id (expected: HIGH cardinality - ~700K unique, 30% sparse)'
\echo '  - application_id (expected: LOW cardinality - 200 unique)'
\echo '  - log_level (expected: VERY LOW cardinality - 6 unique)'
\echo ''
\echo 'Validation results:'
\echo ''

SELECT * FROM logs_validation.validate_bloom_candidates(
    'pg_temp',
    'log_entries_sample',
    ARRAY['trace_id', 'request_id', 'user_id', 'session_id', 'application_id', 'log_level', 'error_code']
);

\echo ''
\echo '===================================================='
\echo ''

-- =====================================================
-- Step 4: Cardinality Summary for All Columns
-- =====================================================

\echo 'Cardinality summary for ALL columns:'
\echo ''

SELECT
    attname AS column_name,
    n_distinct,
    CASE
        WHEN n_distinct >= 0 THEN n_distinct::BIGINT
        ELSE (1000000 * ABS(n_distinct))::BIGINT
    END AS estimated_unique_values,
    CASE
        WHEN ABS(n_distinct) >= 1000 THEN '✅ Bloom filter recommended'
        WHEN ABS(n_distinct) >= 100 THEN '🟠 Borderline for bloom'
        WHEN ABS(n_distinct) >= 10 THEN '📊 MinMax only'
        ELSE '❌ Skip (too low)'
    END AS recommendation,
    null_frac AS null_fraction,
    avg_width AS avg_bytes
FROM pg_stats
WHERE schemaname = 'pg_temp'
  AND tablename = 'log_entries_sample'
ORDER BY ABS(n_distinct) DESC;

\echo ''

-- =====================================================
-- Step 5: Sparse Column Analysis
-- CRITICAL for log analytics (many NULL fields)
-- =====================================================

\echo '===================================================='
\echo 'SPARSE COLUMN ANALYSIS'
\echo '===================================================='
\echo ''
\echo 'PAX sparse filtering is HIGHLY effective for logs'
\echo '(error_code, stack_trace, user_id are sparse)'
\echo ''

SELECT
    attname AS column_name,
    null_frac AS null_fraction,
    CASE
        WHEN null_frac > 0.5 THEN '✅ HIGHLY SPARSE - excellent for PAX'
        WHEN null_frac > 0.2 THEN '✅ MODERATELY SPARSE - good for PAX'
        WHEN null_frac > 0.05 THEN '🟠 SLIGHTLY SPARSE'
        ELSE '⚪ DENSE'
    END AS sparse_verdict,
    avg_width AS avg_bytes,
    CASE
        WHEN null_frac > 0.2 THEN 'PAX will save significant storage on NULL values'
        ELSE 'Normal storage expected'
    END AS expected_benefit
FROM pg_stats
WHERE schemaname = 'pg_temp'
  AND tablename = 'log_entries_sample'
  AND null_frac > 0.05
ORDER BY null_frac DESC;

\echo ''

-- =====================================================
-- Step 6: Memory Requirements Calculation
-- =====================================================

\echo '===================================================='
\echo 'MEMORY REQUIREMENTS FOR CLUSTERING'
\echo '===================================================='
\echo ''
\echo 'Target table size: 10,000,000 rows'
\echo ''

SELECT * FROM logs_validation.calculate_cluster_memory(10000000);

\echo ''

-- =====================================================
-- Step 7: Expected Configuration Summary
-- =====================================================

\echo '===================================================='
\echo 'EXPECTED CONFIGURATION SUMMARY'
\echo '===================================================='
\echo ''
\echo 'Based on cardinality analysis:'
\echo ''
\echo 'SAFE for bloom filters (cardinality >= 1000):'
\echo '  ✅ trace_id (~1,000,000 unique)'
\echo '  ✅ request_id (~1,000,000 unique)'
\echo '  ✅ user_id (~700,000 unique, 30% NULL)'
\echo '  ✅ session_id (~1,000+ unique)'
\echo ''
\echo 'UNSAFE for bloom filters (cardinality < 1000):'
\echo '  ❌ application_id (200 unique) - Use minmax only'
\echo '  ❌ log_level (6 unique) - Use minmax only'
\echo '  ❌ error_code (50 unique) - Use minmax only'
\echo '  ❌ environment (3 unique) - Use minmax only'
\echo '  ❌ region (6 unique) - Use minmax only'
\echo ''
\echo 'SPARSE COLUMNS (excellent for PAX):'
\echo '  ✨ stack_trace (95% NULL) - Massive storage savings'
\echo '  ✨ error_code (95% NULL) - Massive storage savings'
\echo '  ✨ user_id (30% NULL) - Significant storage savings'
\echo ''
\echo 'RECOMMENDED PAX CONFIGURATION:'
\echo '  bloomfilter_columns=''trace_id,request_id'''
\echo '  minmax_columns=''log_date,log_timestamp,application_id,log_level,http_status_code,response_time_ms'''
\echo '  maintenance_work_mem: See calculation above'
\echo ''

-- =====================================================
-- Cleanup
-- =====================================================

DROP TABLE IF EXISTS log_entries_sample;

\echo '===================================================='
\echo 'Cardinality analysis complete!'
\echo '===================================================='
\echo ''
\echo 'Next: Phase 3 - Generate safe PAX configuration'
\echo 'Run: psql -f sql/03_generate_config.sql'
\echo ''
